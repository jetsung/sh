#!/usr/bin/env bash

#============================================================
# 文件名: frp.sh
# Description: 安装 frp
# URL: https://github.com/fatedier/frp
# 作者: Jetsung Chan <i@jetsung.com>
# 版本: 1.0
# 创建日期: 2025-02-11
# 更新日期: 2025-02-11
#============================================================

set -eu

IN_CHINA="${CHINA:-}"
CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

REPO="fatedier/frp"

sudo_exec() {
    if [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

# 判断软件是否已安装（适应不同系统的包管理器）
is_installed() {
    case "$OS_ID" in
        debian|ubuntu|linuxmint|popos)
            dpkg -s "$1" >/dev/null 2>&1
            ;;
        rhel|centos|fedora|rocky|almalinux)
            rpm -q "$1" >/dev/null 2>&1
            ;;
        alpine)
            apk info "$1" >/dev/null 2>&1
            ;;
        arch|manjaro)
            pacman -Qs "$1" >/dev/null 2>&1
            ;;
        *)
            echo "Unsupported distribution: $OS_ID" >&2
            exit 1
            ;;
    esac
}

# 检测系统类型并设置包管理器命令
detect_os() {
    if [ -f /etc/os-release ]; then
        OS_ID=$(grep -E "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [ -f /etc/redhat-release ]; then
        OS_ID="rhel"
    else
        echo "Cannot detect OS type!" >&2
        exit 1
    fi

    case "$OS_ID" in
        debian|ubuntu|linuxmint|popos)
            PKG_INSTALL_CMD="apt install -y -q"
            UPDATE_CMD="apt update -q -y"
            ;;
        rhel|centos|fedora|rocky|almalinux)
            PKG_INSTALL_CMD="dnf install -y -q"
            UPDATE_CMD="dnf makecache"
            ;;
        alpine)
            PKG_INSTALL_CMD="apk add --no-cache"
            UPDATE_CMD="apk update"
            ;;
        arch|manjaro)
            PKG_INSTALL_CMD="pacman -Sy --noconfirm"
            UPDATE_CMD="pacman -Sy"
            ;;
        *)
            echo "Unsupported distribution: $OS_ID" >&2
            exit 1
            ;;
    esac
}

upgade_package_manager() {
    sudo_exec "$UPDATE_CMD" >/dev/null 2>&1  # 更新软件源    
}

# 安装软件（$@: 需要安装的软件列表）
install_packages() {
    echo "$@" | tr ' ' '\n' | while IFS='' read -r pkg; do 
        if is_installed "$pkg"; then
            echo "$pkg is already installed. Skipping..."
        else
            echo "Installing $pkg..."
            sudo_exec "$PKG_INSTALL_CMD" "$pkg" >/dev/null 2>&1
        fi
    done
}

get_arch() {
    uname -m | tr '[:upper:]' '[:lower:]'
}

get_os() {
    uname | tr '[:upper:]' '[:lower:]'
}

check_installed() {
    soft="${1:-}"
    if command -v "$soft" >/dev/null 2>&1; then
        printf "\033[32m%s is already installed\033[0m\n" "$soft"
        return 0
    fi
    return 1
}

check_in_china() {
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
        IN_CHINA=1
    fi
}

get_download_url() {
    download_url="https://api.github.com/repos/$REPO/releases/latest"

    if [ -n "$IN_CHINA" ]; then
        download_url=$(echo "$download_url" | sed "s#https://#${CDN_URL}#")
    fi

    OS="$(get_os)"
    ARCH="$(get_arch)"
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    fi

    file_name="${OS}_${ARCH}"
    if ! curl -fsSL "$download_url" | \
        jq -r '.assets[].browser_download_url' | \
        grep "$file_name" | \
        head -n 1; then

        printf "\033[31mFailed to get %s download url\033[0m\n" "$REPO"
        exit 1
    fi
}

download() {
    download_url=$(get_download_url)

    pkg_name=$(basename "$download_url")

    if [ -n "$IN_CHINA" ]; then
        download_url=$(echo "$download_url" | sed "s#https://#${CDN_URL}#")
    fi    

    if ! curl -fsSL "$download_url" -o "$pkg_name"; then
        printf "\033[31mFailed to download %s\033[0m\n" "$REPO"
        exit 1
    fi

    if [ -f "$pkg_name" ]; then
        tar -zxf "$pkg_name"

        mv "${pkg_name%%.tar.gz}" "frp"

        move_to_bin

        rm -rf "frp" "$pkg_name"
    fi
}

move_to_bin() {
    files="frpc frps"

    # 移动文件
    for file in $files; do
        if ! sudo_exec mv "frp/$file" /usr/local/bin/; then
            printf "\033[31mFailed to move %s to /usr/local/bin\033[0m\n" "$file"
            exit 1
        fi
    done

    files="frpc frps"

    # 移动文件
    for file in $files; do
        if ! sudo_exec mv "frp/${file}.toml" /etc/; then
            printf "\033[31mFailed to move %s to /etc/\033[0m\n" "${file}.toml"
            exit 1
        fi
    done       
}

main() {
    if ! check_installed frpc; then
        if [ -z "$IN_CHINA" ]; then
            check_in_china
        fi
    
        detect_os

        # upgade_package_manager

        install_packages jq

        if [ $# -eq 0 ]; then
            download
        fi
    fi

    if ! check_installed frpc; then
        printf "\033[31mFailed to install frp\033[0m\n"
        exit 1
    fi
}

main "$@"
