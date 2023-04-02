#!/bin/sh

set -eu

NEXTCLOUD_VERSION=25
WEBROOT=/usr/local/www

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
install -d -m 770 -o mysql -g mysql "$DBDIR"

# Create nextcloud data folder outside of web root
DATADIR=/mnt/data
install -d -m 770 -o www -g www "$DATADIR"

# Make the default log directory and create the log file early to satisfy fail2ban
LOGDIR=/var/log/nextcloud
mkdir "$LOGDIR"
touch "$LOGDIR"/nextcloud.log
chown -R www:www "$LOGDIR"

# create sessions tmp dir outside nextcloud installation
SESSIONDIR="${WEBROOT}/nextcloud-sessions-tmp"
install -d -m 770 -o www -g www "$SESSIONDIR"

export LC_ALL=C
# https://docs.nextcloud.com/server/13/admin_manual/installation/installation_wizard.html do not use the same name for user and db
USER="dbadmin"
DB="nextcloud"
NCUSER="ncadmin"
PASS="$(openssl rand --hex 8)"
NCPASS="$(openssl rand --hex 8)"

# Save the config value with the data
INFO_PATH="${DATADIR}/NEXTCLOUD_INFO"
cat >"$INFO_PATH" <<__INFO__
Database Name: ${DB}
Database User: ${USER}
Database Password: ${PASS}

Nextcloud Admin User: ${NCUSER}
Nextcloud Admin Password: ${NCPASS}
__INFO__

# Symlink for the expected iocage plugin info
IOCAGE_INFO_PATH=/root/PLUGIN_INFO
ln -s "$INFO_PATH" "$IOCAGE_INFO_PATH"

# Enable the necessary services
sysrc -f /etc/rc.conf nginx_enable="YES"
sysrc -f /etc/rc.conf php_fpm_enable="YES"
sysrc -f /etc/rc.conf redis_enable="YES"
sysrc -f /etc/rc.conf fail2ban_enable="YES"
sysrc -f /etc/rc.conf mysql_enable="YES"
sysrc -f /etc/rc.conf mysql_dbdir="$DBDIR"

# Start the services
service mysql-server start 2>/dev/null
service redis start 2>/dev/null
service fail2ban start 2>/dev/null
service php-fpm start 2>/dev/null
service nginx start 2>/dev/null

# Configure MariaDB
mysqladmin -u root password "$PASS"
mysql -u root -p"$PASS" --connect-expired-password <<__SQL__
ALTER USER 'root'@'localhost' IDENTIFIED BY '${PASS}';
CREATE DATABASE ${DB};
GRANT ALL PRIVILEGES ON ${DB}.* TO '${USER}'@'localhost' IDENTIFIED BY '${PASS}';
FLUSH PRIVILEGES;
__SQL__

# Download Nextcloud
NC="latest-${NEXTCLOUD_VERSION}.tar.bz2"
fetch -o /tmp \
    https://download.nextcloud.com/server/releases/"$NC" \
    https://download.nextcloud.com/server/releases/"$NC".asc \
    https://nextcloud.com/nextcloud.asc

# Verify artifact's GPG signature"
gpg --import /tmp/nextcloud.asc >/dev/null 2>/dev/null
gpg --verify "/tmp/${NC}".asc >/dev/null 2>/dev/null

NC_WEBROOT="${WEBROOT}/nextcloud"
tar xjf "/tmp/${NC}" -C "$NC_WEBROOT" --strip-components=1

# Give full ownership of the nextcloud directory to www
chown -R www:www "$NC_WEBROOT"
# Removing rwx permission on the nextcloud folder to others users
chmod -R o-rwx "$NC_WEBROOT"

# Finalize Nextcloud installation
occ "maintenance:install \
  --database=\"mysql\" \
  --database-name=\"nextcloud\" \
  --database-user=\"${USER}\" \
  --database-pass=\"${PASS}\" \
  --database-host=\"localhost\" \
  --admin-user=\"${NCUSER}\" \
  --admin-pass=\"${NCPASS}\" \
  --data-dir=\"${DATADIR}\""

occ "background:cron"
occ "config:system:set trusted_domains 1 --value='${IOCAGE_HOST_ADDRESS}'"
