#!/bin/sh

##===----------------------------------------------------------------------===##
# 
# This file is Modular Inc proprietary.
# 
##===----------------------------------------------------------------------===##

set -eu

usage() {
  echo "usage: MODULAR_AUTH= $0"
  exit 2
}

if [ "$#" -ne "0" ]; then
  echo "error: invalid arguments."
  usage
elif [ "x${MODULAR_AUTH:-}" = "x" ]; then
  echo "error: no MODULAR_AUTH provided."
  usage
fi

maybe_sudo() {
  if [ "$(whoami)" = "root" ]; then
    "$@"
  elif type sudo > /dev/null; then
    sudo -E "$@"
  else
    echo "Sorry, either root or 'sudo' is required."
    return 1
  fi
}

remote_script() {
  # Prefer curl over wget, but wget is available by default. We shouldn't need
  # any fallback path where packages are installed. Note that for older shells
  # we do not have pipefail available, therefore ensure that on failure we pipe
  # in a failure that will result in failure of the function.
  if type curl > /dev/null; then
    (curl -1sLf "$1" || echo "exit 1") | maybe_sudo bash
  elif type wget > /dev/null; then
    (wget -q -O - "$1" || echo "exit 1") | maybe_sudo bash
  else
    echo "Sorry, one of 'curl' or 'wget' is required."
    return 1
  fi
}

# Reliably detecting whether a system is Deb-based or RPM-based can be tricky,
# as both tools can be installed on a system. Complex cases may need to fall
# back to manual setup, however it should be the case Debian-deriviatives have
# /etc/debian_version, while this file should not be present in
# non-Debian-based systems.
if [ "$(uname)" = "Linux" ] && [ -f /etc/debian_version ]; then
  remote_script "https://dl.modular.com/${URL_SLUG:-public/installer}/setup.deb.sh"
  maybe_sudo apt install -yq --reinstall modular
elif [ "$(uname)" = "Linux" ] && type rpm > /dev/null && type dnf > /dev/null; then
  remote_script "https://dl.modular.com/${URL_SLUG:-public/installer}/setup.rpm.sh"
  maybe_sudo dnf -yq install modular || \
  (maybe_sudo dnf -q list installed modular &>/dev/null && \
  maybe_sudo dnf -yq reinstall modular)
elif [ "$(uname)" = "Linux" ] && type rpm > /dev/null && type yum > /dev/null; then
  remote_script "https://dl.modular.com/${URL_SLUG:-public/installer}/setup.rpm.sh"
  maybe_sudo yum -yq install modular || \
  (maybe_sudo yum -q list installed modular &>/dev/null && \
  maybe_sudo yum -yq reinstall modular)
else
  echo "Sorry, this system is not recognized. Please visit https://www.modular.com/mojo to learn about supported platforms. You can also build and run a Mojo container by following instructions at https://github.com/modularml/mojo."
  exit 1
fi

modular auth "$MODULAR_AUTH"

cat << EOF
__  __ _ _ _ 
|  \/  | ___ __| |_ _| | __ _ _ __ 
| |\/| |/ _ \ / _\` | | | | |/ _\` | '__|
| |  | | (_) | (_| | |_| | | (_| | | 
|_|  |_|\___/ \__,_|\__,_|_|\__,_|_|

Welcome to the Modular CLI!
For info about this tool, type "modular --help".
To install Mojo🔥, type "modular install mojo".
For Mojo documentation, see https://docs.modular.com/mojo.
To chat on Discord, visit https://discord.gg/modular.
To report issues, go to https://github.com/modularml/mojo/issues.
EOF

