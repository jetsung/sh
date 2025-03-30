#!/usr/bin/env bash

set -e
# set -eux

# echo "Postremove script"

if [[ -f /etc/systemd/system/shortener.service ]]; then
  rm -rf /etc/systemd/system/shortener.service
fi

if [[ -e /usr/local/bin/shortener ]]; then
  rm -rf /usr/local/bin/shortener
fi

# if [[ -d /etc/shortener ]]; then
#   rm -rf /etc/shortener
# fi