#!/usr/bin/env bash

#============================================================
# File: just.sh
# Description: 构建工具
# URL: https://fx4.cn/just
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.1
# CreatedAt: 2025-03-28
# UpdatedAt: 2025-08-02
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
    curl -fsSL "$repo_api_url" | jq -r --arg arch "$ARCH" --arg platform "$PLATFORM" --arg os "$OS" '.assets[] | select(.name | test("\($arch)-\($platform)-\($os)")) | .browser_download_url'
}

download_exact() {
    local download_file="tmp.tar.gz"
    local file_bin="just"
    TMP_DIR=$(mktemp -d /tmp/just.XXXXXX)
    
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

    sudo_exec mv "${file_bin}" "/usr/local/bin/${file_bin}"

    sudo_exec mkdir -p "/usr/local/share/man/man1"
    sudo_exec mv "${file_bin}.1" "/usr/local/share/man/man1/"

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
    if [[ "$OS" = "darwin" ]]; then
        PLATFORM="apple"
    fi

    DOWNLOAD_URL="$(get_download_url casey/just)"

    download_exact

    echo ""

    if ! check_is_command "just"; then
        echo "just has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "just has been installed successfully!"
    echo ""
    just --help
    echo ""
    just --version
    echo ""
}

main "$@"
