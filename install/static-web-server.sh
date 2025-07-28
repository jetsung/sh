#!/usr/bin/env bash

#============================================================
# File: static-web-server.sh
# Description: 安装 static-web-server
# URL: https://s.fx4.cn/yocoYx
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-07-28
# UpdatedAt: 2025-07-28
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
    if [[ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" == "000" ]]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
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
    _repo="static-web-server/static-web-server"
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${_repo}/releases/latest")
    curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "$FLITER_STR"
}

download_exact() {
    DOWNLOAD_FILE="tmp.tar.gz"
    FILE_BIN="static-web-server"  

    _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    if ! curl -fsSL "$_download_url" -o "$DOWNLOAD_FILE"; then
        echo "Error: Failed to download $DOWNLOAD_FILE"
        exit 1
    fi

    if ! tar -xzf "$DOWNLOAD_FILE"; then 
        echo "Error: Extraction failed"
        rm -f "$DOWNLOAD_FILE"
        exit 1
    fi  

    sudo_exec mv ./*"${FLITER_STR}/${FILE_BIN}" /usr/local/bin/

    rm -rf "$DOWNLOAD_FILE" ./*"${FLITER_STR}" 
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    PLATFORM="unknown"
    LIBC_VERSION=""
    if [[ "$OS" == "windows" ]]; then
        PLATFORM="pc"
    elif [[ "$OS" == "darwin" ]]; then
        PLATFORM="apple"
    elif [[ "$OS" == "linux" ]]; then
        PLATFORM="unknown"
        LDD_VERSION=$(ldd --version 2>/dev/null)
        if [[ "$LDD_VERSION" == *"GNU libc"* ]] || [[ "$LDD_VERSION" == *"GLIBC"* ]]; then
            LIBC_VERSION="-gnu"
        elif [[ "$LDD_VERSION" == *"musl"* ]]; then
            LIBC_VERSION="-musl"
        fi
    else
        echo "Error: Unsupported OS: $OS"
        exit 1
    fi

    FLITER_STR="${ARCH}-${PLATFORM}-${OS}${LIBC_VERSION}"
    DOWNLOAD_URL="$(get_download_url)"

    download_exact

    echo ""
    echo "static-web-server has been installed successfully!"
    echo ""
    static-web-server --version
    echo ""    
}

main "$@"