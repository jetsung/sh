#!/usr/bin/env bash

#============================================================
# 文件名: redis.sh
# Description: 安装 Redis
# URL: 
# 作者: Jetsung Chan <i@jetsung.com>
# 版本: 1.0
# 创建日期: 
# 更新日期: 
#============================================================

install_centos_libs() {
  dnf install -y gcc \
  gcc-c++ \
  autoconf \
  automake \
  libtool \
  make \
  cmake
}

do_install() {
  make install PREFIX=/usr/local/redis
  ln -s /usr/local/redis/bin/* /usr/local/bin/
  mkdir /usr/local/redis/{etc,var}
  cp redis.conf /usr/local/redis/etc/
  sed -i "s@logfile.*@logfile /usr/local/redis/var/redis.log@" /usr/local/redis/etc/redis.conf
  sed -i 's@pidfile.*@pidfile /run/redis/redis.pid@' /usr/local/redis/etc/redis.conf  
  sed -i "s@^dir.*@dir /usr/local/redis/var@" /usr/local/redis/etc/redis.conf 
  sed -i "s@^# bind 127.0.0.1@bind 127.0.0.1@" /usr/local/redis/etc/redis.conf
  sed -i 's@daemonize no@daemonize yes@' /usr/local/redis/etc/redis.conf  
  sed -i 's@^supervised.*@supervised systemd@' /usr/local/redis/etc/redis.conf  

  mkdir /run/redis
  cp utils/systemd-redis_server.service /lib/systemd/system/redis-server.service
  sed -i "s@^ExecStart.*@ExecStart=/usr/local/redis/bin/redis-server /usr/local/redis/etc/redis.conf@" /lib/systemd/system/redis-server.service
  sed -i "s@^Type=.*@Type=forking@" /lib/systemd/system/redis-server.service
  systemctl enable redis-server
  systemctl start redis-server
}

install_centos_libs

do_install



