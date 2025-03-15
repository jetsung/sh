#!/usr/bin/env bash

#============================================================
# File: aliyunpan.sh
# Description: 安装 aliyunpan
# URL: https://s.asfd.cn/a21f20b9
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-05
# UpdatedAt: 2025-03-05
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
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}

get_download_url() {
    repo_api_url="${CDN_URL}https://api.github.com/repos/tickstep/aliyunpan/releases/latest" 
    curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "${OS}-${ARCH}"
}

download_exact() {
    DOWNLOAD_FILE="aliyunpan.zip"
    FILE_DIR="aliyunpan"  

    if ! curl -fsSL "${CDN_URL}${DOWNLOAD_URL}" -o "$DOWNLOAD_FILE"; then
        echo "Error: Failed to download $DOWNLOAD_FILE"
        exit 1
    fi

    if ! unzip -q -f aliyunpan.zip; then
        echo "Error: Extraction failed"
        rm -f "$DOWNLOAD_FILE"
        exit 1
    fi

    mv "${FILE_DIR}-"* "$FILE_DIR"

    if [[ -d "/opt/${FILE_DIR}" ]]; then
        sudo_exec rm -rf /opt/"${FILE_DIR}"
    fi

    if ! sudo_exec mv "$FILE_DIR" /opt/; then
        printf "\033[31mFailed to move %s to /opt\033[0m\n" "$FILE_DIR"
        exit 1
    fi

    # 若存在转链接则删除
    if [[ -f "/usr/local/bin/aliyunpan" ]]; then
        sudo_exec rm -f /usr/local/bin/aliyunpan
    fi

    if ! sudo_exec ln -sf "/opt/${FILE_DIR}/aliyunpan" "/usr/local/bin/aliyunpan"; then
        printf "\033[31mInstall %s failed, Please Contact the author! \033[0m" "$FILE_DIR"
        kill -9 $$
    fi

    rm -rf "$DOWNLOAD_FILE" 
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    fi    

    DOWNLOAD_URL="$(get_download_url)"

    download_exact

    echo ""
    echo "aliyunpan has been installed successfully!"
    echo ""
    aliyunpan --version
    echo ""
}

main "$@"