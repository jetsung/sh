#!/usr/bin/env bash

#============================================================
# File: frp.sh
# Description: 安装 frp
# URL: https://s.asfd.cn/
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-02-11
# UpdatedAt: 2025-03-07
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

is_command() {
    command -v "$1" >/dev/null 2>&1
}

is_in_china() {
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}

get_download_url() {
    repo_api_url="${CDN_URL}https://api.github.com/repos/fatedier/frp/releases/latest" 
    curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "${OS}_${ARCH}"
}

download_exact() {
    DOWNLOAD_FILE="frp.tar.gz"
    FRP_BIN_LIST="frpc frps"

    if ! curl -fsSL "${CDN_URL}${DOWNLOAD_URL}" -o "$DOWNLOAD_FILE"; then
        echo "Error: Failed to download $DOWNLOAD_FILE"
        exit 1
    fi

    if ! tar -xzf "$DOWNLOAD_FILE"; then 
        echo "Error: Extraction failed"
        rm -f "$DOWNLOAD_FILE"
        exit 1
    fi

    sudo_exec mkdir -p /etc/frp

    pushd "frp_"*/ > /dev/null 2>&1
        for FRP_BIN in $FRP_BIN_LIST; do
            if ! sudo_exec mv "$FRP_BIN" /usr/local/bin/; then
                printf "\033[31mFailed to move %s to /usr/local/bin\033[0m\n" "$FRP_BIN"
                exit 1
            fi
            if [[ ! -f "/etc/frp/${FRP_BIN}.toml" ]]; then
                sudo_exec cp "${FRP_BIN}.toml" "/etc/frp/"
            fi
        done
    popd > /dev/null 2>&1

    rm -rf "$DOWNLOAD_FILE" "frp_"*
}

main() {
    if ! is_in_china; then
        CDN_URL=""
    fi

    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    fi

    DOWNLOAD_URL="$(get_download_url)"

    download_exact

    echo ""
    echo "frp has been installed successfully"
    echo ""
    echo "frps --version: $(frps --version)"
    echo "frpc --version: $(frpc --version)"
    echo ""
}

main "$@"
