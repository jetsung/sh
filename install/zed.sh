#!/usr/bin/env bash

#============================================================
# File: zed.sh
# Description: 安装 Zed 编辑器
# URL: https://s.asfd.cn/28259340
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-17
# UpdatedAt: 2025-03-17
#============================================================

if [[ -n "$DEBUG" ]]; then
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

# 判断是否为 URL 的函数
check_is_url() {
    local url="$1"
    # 正则表达式匹配 URL
    if [[ "$url" =~ ^https?://[^[:space:]]+ ]]; then
        return 0  # 是 URL
    else
        return 1  # 不是 URL
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

# 保持最末只有一个斜杠
keep_a_slash() {
    echo "$1" | sed -E 's#/*$#/#'
}

# 检查是否需要去掉第二个 https
remove_second_https() {
    # shellcheck disable=SC2001
    echo "$1" | sed 's|\(https://[^/]\+\)/https://|\1/|g'
}

install_for_linux() {
    repo_api_url="${CDN_URL}https://api.github.com/repos/zed-industries/zed/releases"
    if [[ -z "${PRE_VERSION:-}" ]]; then
        repo_api_url="${repo_api_url}/latest"
    fi
    if [[ -n "$NO_HTTPS" ]]; then
        repo_api_url=$(remove_second_https "$repo_api_url")
    fi

    filename="zed-${OS}-${ARCH}.tar.gz"
    if [[ -n "${PRE_VERSION:-}" ]]; then
        download_url=$(curl -fsSL "$repo_api_url" | jq -r '[.[] | select(.prerelease == true)][0].assets[].browser_download_url' | grep "$filename")
    else
        download_url=$(curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "$filename")
    fi

    download_url="${CDN_URL}${download_url}"
    if [[ -n "$NO_HTTPS" ]]; then
        download_url=$(remove_second_https "$download_url")
    fi

    curl -fsSL "$download_url" -o "$filename"

    local _bin_path="zed${PRE_VERSION:+-preview}.app/bin/zed"
    if [[ "$USER_ID" -eq 0 ]]; then
        _install_path="/opt/"
        sudo_exec tar -xzf "$filename" -C "$_install_path" || {
            echo "Failed to install zed."
            exit 1
        }
    else
        _install_path="$HOME/.local/"
        tar -xzf "$filename" -C "$_install_path" || {
            echo "Failed to install zed."
            exit 1
        }
        rm -rf "$_install_path/bin/zed"
        ln -s "${_install_path}${_bin_path}" "$_install_path/bin/zed"
    fi

    rm -rf "$filename"
}

install_for_macos() {
    repo_api_url="${CDN_URL}https://api.github.com/repos/zed-industries/zed/releases${PRE_VERSION:+/latest}" 
    if [[ -n "$NO_HTTPS" ]]; then
        repo_api_url=$(remove_second_https "$repo_api_url")
    fi

    filename="Zed-${ARCH}.dmg"
    if [[ -n "${PRE_VERSION:-}" ]]; then
        download_url=$(curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "$filename")
    else
        download_url=$(curl -fsSL "$repo_api_url" | jq -r '[.[] | select(.prerelease == true)][0].assets[].browser_download_url' | grep "$filename")
    fi

    download_url="${CDN_URL}${download_url}"
    if [[ -n "$NO_HTTPS" ]]; then
        download_url=$(remove_second_https "$download_url")
    fi

    curl -fsSL "$download_url" -o "$filename"    
    echo ""
    echo "Save the DMG file to $filename"
    echo "Download finished, please open the DMG file and drag Zed.app to your Applications folder."
    echo ""
    exit 0
}

do_install() {
    if [[ "$OS" == "linux" ]]; then
        install_for_linux
    elif [[ "$OS" == "darwin" ]]; then
        install_for_macos
    else 
        echo "Unsupported OS: $OS"
        exit 1
    fi
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")
    CDN_URL=$(keep_a_slash "$CDN_URL")

    # 预览版
    if [[ -n "${1:-}" && ("$1" = "-p" || "$1" = "--pre") ]]; then
        PRE_VERSION=1
    fi

    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"    

    do_install

    echo ""

    if ! check_is_command "zed"; then
        echo "zed has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "zed has been installed successfully!"
    echo ""
    zed --version
    echo ""    
}

main "$@"