#!/usr/bin/env bash

#============================================================
# File: squashfs.sh
# Description: 压缩与解压工具
# URL: https://fx4.cn/squashfs
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-16
# UpdatedAt: 2025-08-16
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

# 支持多个 Linux 平台的依赖安装
install_deps() {
    # 安装依赖包（包含各压缩算法支持）
    if check_is_command "apt-get"; then
        echo "检测到 Debian/Ubuntu 系统，安装依赖..."
        sudo_exec apt-get update
        sudo_exec apt-get install -y build-essential wget git liblzma-dev liblzo2-dev liblz4-dev libzstd-dev zlib1g-dev
    elif check_is_command "yum"; then
        echo "检测到 CentOS/RHEL 系统，安装依赖..."
        sudo_exec yum install -y gcc make wget git xz-devel lzo-devel lz4-devel zstd-devel zlib-devel
    elif check_is_command "apk"; then
        echo "检测到 Alpine 系统，安装依赖..."
        sudo_exec apk add build-base wget git lzo-dev lz4-dev xz-dev zstd-dev zlib-dev
    elif check_is_command "pacman"; then
        echo "检测到 Arch Linux 系统，安装依赖..."
        sudo_exec pacman -Sy --noconfirm base-devel wget git lzo lz4 xz zstd zlib
    else
        echo "未检测到已知包管理器，请手动安装依赖：gcc make wget git lzo lz4 xz zstd zlib"
        return 1
    fi
}

get_download_url() {
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${1}/releases")
    curl -fsSL "$repo_api_url" | grep "browser_download_url" | cut -d '"' -f 4 | head -n 1
}

download_exact() {
    local download_file="tmp.tar.gz"
    TMP_DIR=$(mktemp -d /tmp/squashfs.XXXXXX)

    # shellcheck disable=SC2329
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

    if ! tar -xzf "$download_file" --strip-components=1; then 
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi

    cd squashfs-tools
    make
    sudo_exec make install

    popd >/dev/null
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    DOWNLOAD_URL="$(get_download_url plougher/squashfs-tools)"

    if [[ -z "$DOWNLOAD_URL" ]]; then
        echo "Error: Failed to get download url"
        exit 1
    fi

    install_deps

    download_exact

    echo ""

    if ! check_is_command "mksquashfs"; then
        echo "mksquashfs has not been installed successfully."
        echo ""
        exit 1
    fi

    if ! check_is_command "unsquashfs"; then
        echo "unsquashfs has not been installed successfully."
        echo ""
        exit 1
    fi

    echo ""
    echo "squashfs-tools has been installed successfully!"
    echo ""

    mksquashfs -version
    echo ""
}

main "$@"
