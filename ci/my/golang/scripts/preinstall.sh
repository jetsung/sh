#!/usr/bin/env bash

set -e
# set -eux

# echo "Preinstall script"

if [[ -f /etc/shortener/config.toml ]]; then
  cp /etc/shortener/config.toml /opt/shortener/config.toml.bak
fi

if [[ ! -d /etc/shortener/data ]]; then
  mkdir -p /etc/shortener/data
fi

exit 0