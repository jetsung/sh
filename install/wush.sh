#!/usr/bin/env bash

#============================================================
# File: wush.sh
# Description: 安装 wush 网络穿透工具
# URL: https://s.fx4.cn/gitlab-runner
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-14
# UpdatedAt: 2025-03-14
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

USER_ID="$(id -u)"

sudo_exec() {
    if [[ "$USER_ID" -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

check_is_command() {
    command -v "$1" >/dev/null 2>&1
}

check_in_china() {
    if [[ -n "${CN:-}" ]]; then
        return 0 # 手动指定
    fi
    if [[ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}

check_url_connection() {
    _url="${1:-}"
    if [[ -z "$_url" ]]; then
        return 1
    fi

    if [[ -n "${CN:-}" ]]; then
        return 1 # 手动指定
    fi    

    _check_url=$(echo "$_url" | cut -d '/' -f 1-3)
    if [[ $(curl -s -m 3 -o /dev/null -w "%{http_code}" "$_check_url") != "200" ]]; then
        return 0 # 联通
    fi
    return 1 # 不能联通
}

# 若为 https://xxx.xx 不以 / 结尾，则组合时去掉加速网址的 https://
#   格式为 https://file.xxx.io/github.com/
# 若为 https://xxx.xx/ 以 / 结尾，则组合时保留加速网址的 https://
#   格式为 https://xxx.xx/https://github.com/
check_remove_https() {
    if [[ -n "$1" && "${1: -1}" != "/" ]]; then
        echo 1
    fi    
}

do_remove_https() {
    local _url="$1"
    if [[ -n "$NO_HTTPS" ]]; then
        # shellcheck disable=SC2001
        echo "$_url" | sed 's|https:/||2'

    else 
        echo "$_url"
    fi
}

get_download_url() {
    local _suffix="${1:-}"
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/coder/wush/releases/latest")
    curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "${OS}_${ARCH}${_suffix}"
}

get_system_info() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "deepin" ]]; then
            echo "debian"
        elif [[ "$ID" == "centos" || "$ID" == "fedora" || "$ID" == "redhat" ]]; then
            echo "redhat"
        else
            echo "unknown"
        fi
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    else
        echo "unknown"
    fi    
}

do_install() {
    case "${METHOD,,}" in
        "p" | "package")
            install_with_package
            ;;

        "b" | "binary" | *)
            install_with_binary
            ;;
    esac
}

install_with_package() {
    echo "Installing wush with package (${SYSTEM})..."

    local _method=""
    if [[ "$SYSTEM" == "debian" ]]; then
        _download_url=$(get_download_url ".deb")
        _download_url=$(do_remove_https "${CDN_URL}${_download_url}") 
        local _pkg_file="/tmp/wush.deb"
        curl -L --output "$_pkg_file" "$_download_url"
        sudo_exec dpkg -i "$_pkg_file"
        rm -f "$_pkg_file"
    elif [[ "$SYSTEM" == "redhat" ]]; then
        _download_url=$(get_download_url ".rpm")
        _download_url=$(do_remove_https "${CDN_URL}${_download_url}") 
        local _pkg_file="/tmp/wush.rpm"
        curl -L --output "$_pkg_file" "$_download_url"
        sudo_exec rpm -i "$_pkg_file"
        rm -f "$_pkg_file"
    else
        echo "Unsupported system: $SYSTEM"
        exit 1
    fi
}

install_with_binary() {
    echo "Installing wush with binary (${SYSTEM} ${OS} ${ARCH} .tar.gz)..."

    DOWNLOAD_FILE="wush.tar.gz"
    FILE_BIN="wush"  

    _download_url=$(get_download_url ".tar.gz")
    _download_url=$(do_remove_https "${CDN_URL}${_download_url}") 

    if ! curl -fsSL "$_download_url" -o "$DOWNLOAD_FILE"; then
        echo "Error: Failed to download $DOWNLOAD_FILE"
        exit 1
    fi

    if ! tar -xzf "$DOWNLOAD_FILE"; then 
        echo "Error: Extraction failed"
        rm -f "$DOWNLOAD_FILE"
        exit 1
    fi  

    sudo_exec mv "$FILE_BIN" /usr/local/bin/

    rm -rf "$DOWNLOAD_FILE" LICENSE README.md      
}

judgment_parameters() {
  while getopts "m:" opt; do
    case "$opt" in
      m)
        METHOD="$OPTARG"
        ;;

      \?)
        echo "Usage: $0 [-m <b|binary|p|package>]"
        exit 1
        ;;
    esac
  done
}

main() {
    judgment_parameters "$@"

    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    SYSTEM="$(get_system_info)"

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    case "$ARCH" in
        "x86_64")
            ARCH="amd64"
            ;;
        "aarch64")
            ARCH="arm64"
            ;;
    esac

    METHOD="${METHOD:-b}"

    do_install

    echo ""

    if ! check_is_command "wush"; then
        echo "wush has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "wush has been installed successfully!"
    echo ""
    wush --version
    echo ""
}

main "$@"
