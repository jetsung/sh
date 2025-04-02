#!/usr/bin/env bash

set -e
# set -eux

#echo "Postinstall script"

if [[ -f /opt/shortener/config/config.toml.bak ]]; then
  mv /opt/shortener/config/config.toml.bak /opt/shortener/config/config.toml
fi

if [[ ! -f /opt/shortener/config/config.toml ]]; then
  mkdir -p /opt/shortener/config
  cp /opt/shortener/config.toml /opt/shortener/config/config.toml
fi

if [[ -e /usr/local/bin/shortener ]]; then
  rm -rf /usr/local/bin/shortener
fi

ln -s /opt/shortener/shortener /usr/local/bin/shortener

if [[ -f /opt/shortener/shortener.service ]]; then
  cp /opt/shortener/shortener.service /etc/systemd/system/shortener.service

  systemctl enable shortener.service
  systemctl start shortener.service
fi

exit 0
