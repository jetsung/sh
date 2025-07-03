#!/usr/bin/env bash

#============================================================
# File: vsd.sh
# Description: 安装 m3u8 下载器 （vsd）
# URL: https://s.fx4.cn/vsd
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-07-03
# UpdatedAt: 2025-07-03
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
    local repo="clitic/vsd"
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${repo}/releases/latest")
    #curl -fsSL "$repo_api_url" | jq -r '.assets[] | select(.name | test("x86_64.*linux")) | .browser_download_url'
    curl -fsSL "$repo_api_url" | jq -r --arg os "$OS" --arg arch "$ARCH" '.assets[] | select(.name | test("\($arch).*\($os)")) | .browser_download_url'
}

download_exact() {
    DOWNLOAD_FILE="vsd.tar.xz"
    FILE_BIN="vsd"  

    _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    if ! curl -fsSL "$_download_url" -o "$DOWNLOAD_FILE"; then
        echo "Error: Failed to download $DOWNLOAD_FILE"
        exit 1
    fi

    if ! tar -xJf "$DOWNLOAD_FILE"; then 
        echo "Error: Extraction failed"
        rm -f "$DOWNLOAD_FILE"
        exit 1
    fi  

    sudo_exec mv "$FILE_BIN" /usr/local/bin/

    rm -rf "$DOWNLOAD_FILE"
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"

    DOWNLOAD_URL="$(get_download_url)"

    download_exact

    echo ""
    echo "vsd has been installed successfully!"
    echo ""
    vsd --help
    echo ""    
}

main "$@"
