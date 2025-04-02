#!/usr/bin/env bash

set -e
# set -eux

# echo "Preinstall script"

if [[ -f /opt/shortener/config/config.toml ]]; then
  mv /opt/shortener/config/config.toml /opt/shortener/config/config.toml.bak
fi

exit 0