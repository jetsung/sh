#!/usr/bin/env bash

# ORIGIN: https://framagit.org/-/snippets/7181/raw/main/debfetch.sh

set -euo pipefail

judgment_parameters() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
    '-h' | '--help')
      HELP='1'
      break
      ;;

    -n | --name)
      if [[ -z "${2:?error: Please specify the correct name.}" ]]; then
        exit 1
      fi
      NAME="$2"
      shift
      ;;

    -u | --url)
      if [[ -z "${2:?error: Please specify the correct url.}" ]]; then
        exit 1
      fi
      URL="$2"
      shift
      ;;

    -s | --skip)
      SKIP='1'
      ;;

    *)
      echo "$0: unknown option -- -"
      exit 1
      ;;
    esac
    shift
  done
}

show_help() {
  echo "usage: $0 [ options ]"
  echo '  -h, --help      Show help'
  echo '  -n, --name      App name'
  echo '  -u, --url       App url'
  exit 0
}

fetch_deb() {
  if [[ ! "$1" =~ .deb$ ]]; then
    echo -e "The url is not a deb package:\n$1\n"
    exit 1
  fi

  GITHUB="${GITHUB:-https://github.com}"
  url=${1/https:\/\/github.com/"$GITHUB"/}

  name="${2:-$(mktemp -t DEB.APT_XXXX)}"

  if file "$name" | grep -v 'Debian binary package'; then
    rm -rf "$name"
  fi

  if [[ ! -f "$name" ]]; then
    echo "Save to '$name' from $url"
    curl -fsSL -o "$name" "$url"
    echo
  fi

  if file "$name" | grep -v 'Debian binary package'; then
    echo -e "The file is not a deb package:\n$name\n"
    exit 1
  fi

  move_deb "$name"
}

move_deb() {
  DEB_FULL_PATH="${1:-}"
  PACKAGE_INFO=$(dpkg-deb --info "$DEB_FULL_PATH" | awk '/Package:|Architecture:|Version:|Maintainer:/ {print}')

  # 从提取的信息中获取软件包名称、版本和维护者
  PACKAGE_NAME=$(echo "$PACKAGE_INFO" | awk -F ': ' '/Package:/ {print $2}')
  PACKAGE_ARCH=$(echo "$PACKAGE_INFO" | awk -F ': ' '/Architecture:/ {print $2}')
  PACKAGE_VERSION=$(echo "$PACKAGE_INFO" | awk -F ': ' '/Version:/ {print $2}')
  MAINTAINER=$(echo "$PACKAGE_INFO" | awk -F ': ' '/Maintainer:/ {print $2}')

  # 输出提取的信息
  echo
  echo "Package Name: $PACKAGE_NAME"
  echo "Architecture: $PACKAGE_ARCH"
  echo "Version: $PACKAGE_VERSION"
  echo "Maintainer: $MAINTAINER"

  DEB_TARGET_PATH="${DEB_POOL_PATH}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${PACKAGE_ARCH}.deb"
  echo
  echo "Target deb path: ${DEB_TARGET_PATH}"

  if [[ "$DEB_FULL_PATH" = "$DEB_TARGET_PATH" ]]; then
    echo -e "The same as the target file:\n$DEB_FULL_PATH\n"
    exit 1
  fi

  mv "$DEB_FULL_PATH" "$DEB_TARGET_PATH" || {
    echo "Failed to move $DEB_FULL_PATH to $DEB_TARGET_PATH"
    exit 1
  }
}

set_archconf() {
  if [[ -f "$APT_CONF_PATH" ]]; then
    return
  fi

  Origin="$HEADER_ORIGIN"
  Label="$HEADER_LABEL"
  Codename=stable
  Version=$(date +%Y)
  Architectures=amd64
  Components=main
  Description="$Origin packages"

  tee "$APT_CONF_PATH" <<EOF
Origin: $Origin
Label: $Label
Codename: $Codename
Version: $Version
Architectures: $Architectures
Components: $Components
Description: $Description
EOF
}

upgrade_index() {
  pushd "$APT_ROOT_PATH" >/dev/null 2>&1 || {
    echo "Failed to enter $APT_ROOT_PATH"
    exit 1
  }

  [[ -d "pool/main" ]] || mkdir -p "pool/main"
  [[ -d "dists/stable/main/binary-amd64/" ]] || mkdir -p "dists/stable/main/binary-amd64/"

  dpkg-scanpackages --multiversion --arch amd64 pool/ >"dists/stable/main/binary-amd64/Packages"
  gzip -9 >"dists/stable/main/binary-amd64/Packages.gz" <"dists/stable/main/binary-amd64/Packages"

  DIST_STABLE="dists/stable"
  apt-ftparchive release "$DIST_STABLE" >"$DIST_STABLE/Release"

  sed -i "1r $APT_CONF_PATH" "$DIST_STABLE/Release"

  gpg --default-key "$GPG_KEY" -abs >"$DIST_STABLE/Release.gpg" <"$DIST_STABLE/Release"
  gpg --default-key "$GPG_KEY" -abs --clearsign >"$DIST_STABLE/InRelease" <"$DIST_STABLE/Release"

  popd >/dev/null 2>&1 || {
    echo "Failed to exit $APT_ROOT_PATH"
    exit 1
  }
}

main() {
  judgment_parameters "$@"

  [[ "${HELP:-}" -eq '1' ]] && show_help

  if ! which dpkg-buildpackage >/dev/null 2>&1; then
    echo "dpkg-dev is not installed."
    exit 1
  fi

  APT_ROOT_PATH="${APTPATH:-/root/downloads}"
  DEB_POOL_PATH="${DEBPATH:-$APT_ROOT_PATH/pool/main}"
  APT_CONF_PATH="${APTCONF:-/etc/apt-ftparchive.conf}"
  
  ORGNAME="${ORGNAME:-idev}"
  GPG_KEY="${GPGKEY:-example@example.com}"
  
  echo "APT_ROOT_PATH: $APT_ROOT_PATH"
  echo "DEB_POOL_PATH: $DEB_POOL_PATH"
  echo "APT_CONF_PATH: $APT_CONF_PATH"
  echo "GPG_KEY: $GPG_KEY"
  echo "ORG NAME: $ORGNAME"
  echo

  [[ -d "$DEB_POOL_PATH" ]] || mkdir -p "$DEB_POOL_PATH"

  if [[ -n "${URL:-}" ]]; then
    fetch_deb "$URL" "${NAME:-}"
  fi

  HEADER_ORIGIN="$ORGNAME"
  HEADER_LABEL="$ORGNAME"

  if [[ -z "${SKIP:-}" ]]; then
    set_archconf
    upgrade_index
  fi
}

main "$@"