#!/usr/bin/env bash

set -e
# set -eux

# echo "Preremove script"

if systemctl list-units --type=service | grep -q 'shortener.service'; then
  systemctl stop shortener.service
  systemctl disable shortener.service
fi

exit 0
