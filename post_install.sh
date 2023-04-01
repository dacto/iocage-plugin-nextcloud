#!/bin/sh

set -eu

NEXTCLOUD_VERSION=26
# Load environment variable from /etc/iocage-env
. load_env

# Generate some configuration from templates.
sync_configuration

# Generate self-signed TLS certificates
generate_self_signed_tls_certificates

# Add the www user to the redis group to allow it to access the socket
pw usermod www -G redis

# Create the database directory
DBDIR=/mnt/db
mkdir -m 770 "$DBDIR"
chown mysql:mysql "$DBDIR"

# Enable the necessary services
sysrc -f /etc/rc.conf nginx_enable="YES"
sysrc -f /etc/rc.conf php_fpm_enable="YES"
sysrc -f /etc/rc.conf redis_enable="YES"
sysrc -f /etc/rc.conf fail2ban_enable="YES"
sysrc -f /etc/rc.conf mysql_enable="YES"
sysrc -f /etc/rc.conf mysql_dbdir="$DBDIR"

# Start the service
service nginx start 2>/dev/null
service php-fpm start 2>/dev/null
service mysql-server start 2>/dev/null
service redis start 2>/dev/null

# https://docs.nextcloud.com/server/13/admin_manual/installation/installation_wizard.html do not use the same name for user and db
USER="dbadmin"
DB="nextcloud"
NCUSER="ncadmin"

# Save the config values
echo "$DB" > /root/dbname
echo "$USER" > /root/dbuser
echo "$NCUSER" > /root/ncuser
export LC_ALL=C
openssl rand --hex 8 > /root/dbpassword
openssl rand --hex 8 > /root/ncpassword
PASS=$(cat /root/dbpassword)
NCPASS=$(cat /root/ncpassword)

# Configure mysql
mysqladmin -u root password "${PASS}"
mysql -u root -p"${PASS}" --connect-expired-password <<-EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${PASS}';
CREATE DATABASE ${DB};
GRANT ALL PRIVILEGES ON ${DB}.* TO '${USER}'@'localhost' IDENTIFIED BY '${PASS}';
FLUSH PRIVILEGES;
EOF

# Make the default log directory
mkdir /var/log/nextcloud
chown www:www /var/log/nextcloud

# Install nextcloud
FILE="latest-${NEXTCLOUD_VERSION}.tar.bz2"
if ! fetch -o /tmp \
        https://download.nextcloud.com/server/releases/"${FILE}" \
        https://download.nextcloud.com/server/releases/"${FILE}".asc \
        https://nextcloud.com/nextcloud.asc
then
    echo "Failed to download Nextcloud"
    exit 1
fi

gpg --import /tmp/nextcloud.asc
if ! gpg --verify /tmp/"${FILE}".asc; then
    echo "GPG Signature Verification Failed!"
    echo "The Nextcloud download is corrupt."
    exit 1
fi

tar xjf /tmp/"${FILE}" -C /usr/local/www/
chown -R www:www /usr/local/www/nextcloud/

# Create nextcloud data folder outside of web root
DATADIR=/mnt/data
mkdir -m 770 -p "$DATADIR"
chown www:www "$DATADIR"

# Use occ to complete Nextcloud installation
su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install \
  --database=\"mysql\" \
  --database-name=\"nextcloud\" \
  --database-user=\"${USER}\" \
  --database-pass=\"${PASS}\" \
  --database-host=\"localhost\" \
  --admin-user=\"${NCUSER}\" \
  --admin-pass=\"${NCPASS}\" \
  --data-dir=\"${DATADIR}\""

su -m www -c "php /usr/local/www/nextcloud/occ background:cron"

su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value='${IOCAGE_HOST_ADDRESS}'"

# create sessions tmp dir outside nextcloud installation
mkdir -p /usr/local/www/nextcloud-sessions-tmp >/dev/null 2>/dev/null
chmod o-rwx /usr/local/www/nextcloud-sessions-tmp
chown -R www:www /usr/local/www/nextcloud-sessions-tmp

# Starting fail2ban
service fail2ban start 2>/dev/null

# Removing rwx permission on the nextcloud folder to others users
chmod -R o-rwx /usr/local/www/nextcloud
# Give full ownership of the nextcloud directory to www
chown -R www:www /usr/local/www/nextcloud

echo "Database Name: $DB" > /root/PLUGIN_INFO
echo "Database User: $USER" >> /root/PLUGIN_INFO
echo "Database Password: $PASS" >> /root/PLUGIN_INFO

echo "Nextcloud Admin User: $NCUSER" >> /root/PLUGIN_INFO
echo "Nextcloud Admin Password: $NCPASS" >> /root/PLUGIN_INFO
