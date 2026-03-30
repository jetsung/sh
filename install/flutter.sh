#!/usr/bin/env bash

#============================================================
# File: flutter.sh
# Description: 安装 Flutter SDK
# URL: https://fx4.cn/flutter
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-03-30
# UpdatedAt: 2026-03-30
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
    local _releases_url
    local _release_json

    if [[ -z "$FLUTTER_STORAGE_BASE_URL" ]]; then
        FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"
    fi

    _releases_url=$(do_remove_https "${CDN_URL}${FLUTTER_STORAGE_BASE_URL}/flutter_infra_release/releases/releases_linux.json")
    _release_json=$(curl -fsSL "$_releases_url")

    _base_url=$(echo "$_release_json" | jq -r '.base_url')

    _channel="stable"
    if [[ -n "${PRE_VERSION:-}" ]]; then
        _channel="beta"
    fi

    _archive=$(echo "$_release_json" | jq -r --arg channel "$_channel" '
        first(.releases[] 
        | select(.channel | test("\($channel)"; "i")))
        | .archive
        ')

    echo "${_base_url}/${_archive}"
}

download_exact() {
    local download_file="flutter.tar.xz"
    TMP_DIR=$(mktemp -d /tmp/flutter.XXXXXX)

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

    if ! tar -xJf "$download_file"; then 
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi

    if [[ -d "$HOME/.local/flutter" ]]; then
        rm -rf "$HOME/.local/flutter"
    fi

    mv flutter "$HOME/.local/flutter"
    export PATH="$PATH:$HOME/.local/flutter/bin"

    popd >/dev/null
}

main() {
    # 若自定义则跳过 CDN
    if [[ -n "$FLUTTER_STORAGE_BASE_URL" ]] || ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    # 预览版
    if [[ -n "${1:-}" && ("$1" = "-p" || "$1" = "--pre") ]]; then
        PRE_VERSION=1
    fi

    DOWNLOAD_URL="$(get_download_url)"

    download_exact

    echo ""

    if ! check_is_command "flutter"; then
        echo "flutter has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "flutter has been installed successfully!"
    echo ""
    echo "Please add the following line to your ~/.bashrc or ~/.zshrc:"
    echo "export PATH=\"\$PATH:\$HOME/.local/flutter/bin\""
    echo ""
    flutter --help
    echo ""
    flutter --version
    echo ""        
}

main "$@"