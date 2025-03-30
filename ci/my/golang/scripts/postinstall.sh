#!/usr/bin/env bash

set -e
# set -eux

#echo "Postinstall script"

if [[ -f /opt/shortener/config.toml.bak ]]; then
  mv /opt/shortener/config.toml.bak /etc/shortener/config.toml
elif [[ -f /opt/shortener/config.toml ]]; then
  cp /opt/shortener/config.toml /etc/shortener/config.toml
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
