#!/usr/bin/env bash

#============================================================
# File: static-web-server.sh
# Description: 安装 static-web-server
# URL: https://s.fx4.cn/sws
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
    local url="$1"
    if [[ -n "$NO_HTTPS" ]]; then
        # shellcheck disable=SC2001
        echo "$url" | sed 's|https:/||2'

    else 
        echo "$url"
    fi
}

########################## 以上为通用函数 #########################

get_download_url() {
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${1}/releases/latest")
    curl -fsSL "$repo_api_url" | jq -r --arg arch "$ARCH" --arg os "$OS" --arg platform "$PLATFORM" --arg libc "$LIBC_VERSION" '.assets[] | select(.name | test("\($arch)-\($platform)-\($os)\($libc)")) | .browser_download_url'
}

download_exact() {
    local download_file="tmp.tar.gz"
    local file_bin="static-web-server"
    TMP_DIR=$(mktemp -d /tmp/static-web-server.XXXXXX)
    
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi

    if ! tar -xzf "$download_file"; then 
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi  

    sudo_exec mv "./${file_bin}"*/"${file_bin}" /usr/local/bin/
    
    popd >/dev/null
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

    DOWNLOAD_URL="$(get_download_url static-web-server/static-web-server)"

    download_exact

    echo ""

    if ! check_is_command "static-web-server"; then
        echo "static-web-server has not been installed successfully."
        echo ""
        exit 1
    fi

    echo ""
    echo "static-web-server has been installed successfully!"
    echo ""
    static-web-server --help
    echo ""
    static-web-server --version
    echo ""    
}

main "$@"