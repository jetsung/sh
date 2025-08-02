#!/usr/bin/env bash

#============================================================
# File: ttyd.sh
# Description: 安装 ttyd
# URL: https://s.fx4.cn/ttyd
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
    curl -fsSL "$repo_api_url" | jq -r --arg arch "$ARCH" '.assets[] | select(.name | test("\($arch)")) | .browser_download_url'
}

download_exact() {
    local download_file="ttyd"
    local file_bin="ttyd"
    TMP_DIR=$(mktemp -d /tmp/ttyd.XXXXXX)
    
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

    chmod +x "$file_bin"
    sudo_exec mv "$file_bin" "/usr/local/bin/$file_bin"

    popd >/dev/null
}

make_install() {
    TMP_DIR=$(mktemp -d /tmp/ttyd.XXXXXX)
    
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null    

    _repo_url="https://github.com/${1}.git"
    _git_url=$(do_remove_https "${CDN_URL}${_repo_url}")

    # install deps
    sudo_exec apt-get install -y build-essential cmake git libjson-c-dev libwebsockets-dev

    git clone "$_git_url"
    cd ttyd && mkdir build && cd build
    cmake ..

    make && sudo_exec make install

    popd >/dev/null
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"

    # 编译安装
    if [[ "${1:-}" = "make" ]]; then
        make_install "tsl0922/ttyd"
    else
        DOWNLOAD_URL="$(get_download_url tsl0922/ttyd)"

        download_exact
    fi

    echo ""

    if ! check_is_command "ttyd"; then
        echo "ttyd has not been installed successfully."
        echo ""
        exit 1
    fi    

    echo ""
    echo "ttyd has been installed successfully"
    echo ""
    echo "ttyd --version: $(ttyd --version)"
    echo ""
}

main "$@"
