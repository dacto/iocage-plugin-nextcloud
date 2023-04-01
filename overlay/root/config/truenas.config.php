<?php
$CONFIG = array(
  'one-click-instance' => true,
  'one-click-instance.user-limit' => 100,
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' => array(
    'host' => '/var/run/redis/redis.sock',
    'port' => 0,
  ),
  'logfile' => '/var/log/nextcloud/nextcloud.log',
  'logrotate_size' => 104847600,
);
