#!/usr/bin/env bash

#============================================================
# File: just.sh
# Description: 安装 just 构建工具
# URL: https://s.fx4.cn/hM1Rzj
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-28
# UpdatedAt: 2025-03-28
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

# 保持最末只有一个斜杠
keep_a_slash() {
    if [[ -n "$1" ]]; then
        echo "$1" | sed -E 's#/*$#/#'
    fi
}

# 检查是否需要去掉第二个 https
remove_second_https() {
    # shellcheck disable=SC2001
    echo "$1" | sed 's|\(https://[^/]\+\)/https://|\1/|g'
}

do_install() {
    repo="casey/just"
    repo_api_url="${CDN_URL}https://api.github.com/repos/${repo}/releases/latest" 
    if [[ -n "$NO_HTTPS" ]]; then
        repo_api_url=$(remove_second_https "$repo_api_url")
    fi

    os_arch="${ARCH}-${PLATFORM}-${OS}"
    download_url=$(curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "$os_arch")

    filename_pkg="just.tar.gz"
    file_dir="just"  

    download_url="${CDN_URL}${download_url}"
    if [[ -n "$NO_HTTPS" ]]; then
        download_url=$(remove_second_https "$download_url")
    fi

    if ! curl -fsSL "$download_url" -o "$filename_pkg"; then
        echo "Error: Failed to download $filename_pkg"
        exit 1
    fi

    sudo_exec tar -xzf "$filename_pkg" -C /tmp || {
        echo "Failed to install just."
        exit 1
    }    

    sudo_exec mv "/tmp/just" "/usr/local/bin/${file_dir}"

    sudo_exec mkdir -p "/usr/local/share/man/man1"
    sudo_exec mv "/tmp/just.1" "/usr/local/share/man/man1/"

    rm -rf "$filename_pkg" 
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")
    CDN_URL=$(keep_a_slash "$CDN_URL")

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    PLATFORM="unknown"
    if [[ "$OS" = "darwin" ]]; then
        PLATFORM="apple"
    fi

    do_install

    echo ""

    if ! check_is_command "just"; then
        echo "just has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "just has been installed successfully!"
    echo ""
    just --version
    echo ""
}

main "$@"