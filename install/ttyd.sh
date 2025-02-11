#!/usr/bin/env sh

#============================================================
# 文件名: ttyd.sh
# 描述: 安装 ttyd
# URL: https://github.com/tsl0922/ttyd
# 作者: Jetsung Chan <i@jetsung.com>
# 版本: 1.0
# 创建日期: 2025-02-11
# 更新日期: 2025-02-11
#============================================================

set -eu

IN_CHINA="${CHINA:-}"
CDN_URL="${CDN:-https://c.kkgo.cc/}"

# 检查软件是否安装（适配不同系统）
is_installed() {
    case "$1" in
        debian|ubuntu|linuxmint|popos)
            dpkg -s "$2" >/dev/null 2>&1
            ;;
        rhel|centos|fedora|rocky|almalinux)
            rpm -q "$2" >/dev/null 2>&1
            ;;
        alpine)
            apk info "$2" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

install_deps_debian() {
    sudo_exec apt update

    pkg_list="build-essential cmake jq git libjson-c-dev libwebsockets-dev"
    for pkg in $pkg_list; do
        if ! is_installed "$OS_ID" "$pkg"; then
            echo "Installing $pkg..."
            sudo_exec DEBIAN_FRONTEND=noninteractive apt install -y "$pkg" >/dev/null
        else
            echo "$pkg is already installed. Skipping..."
        fi
    done
}

install_deps_redhat() {
    sudo_exec dnf install -y @development-tools cmake jq git json-c-devel libwebsockets-devel
}

install_deps_alpine() {
    sudo_exec apk add --no-cache build-base cmake jq git json-c-dev libwebsockets-dev
}

detect_and_install() {
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
            install_deps_debian
            ;;
        rhel|centos|fedora|rocky|almalinux)
            install_deps_redhat
            ;;
        alpine)
            install_deps_alpine
            ;;
        *)
            echo "Unsupported distribution: $OS_ID" >&2
            exit 1
            ;;
    esac
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

sudo_exec() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -E "$@"
    fi
}

get_download_url() {
    download_url="https://api.github.com/repos/tsl0922/ttyd/releases/latest"

    if [ -n "$IN_CHINA" ]; then
        download_url=$(echo "$download_url" | sed "s#https://#${CDN_URL}#")
    fi

    if ! curl -fsSL "$download_url" | \
        jq -r '.assets[].browser_download_url' | \
        grep "$(get_arch)" | \
        head -n 1; then

        printf "\033[31mFailed to get ttyd download url\033[0m\n"
        exit 1
    fi
}

download() {
    if [ ! -f ttyd ]; then
        download_url=$(get_download_url)

        if [ -n "$IN_CHINA" ]; then
            download_url=$(echo "$download_url" | sed "s#https://#${CDN_URL}#")
        fi    

        if ! curl -fsSL "$download_url" -o ttyd; then
            printf "\033[31mFailed to download ttyd\033[0m\n"
            exit 1
        fi
    fi
    
    if [ -f ttyd ]; then
        chmod +x ttyd

        move_to_bin
    fi
}

move_to_bin() {
    if ! sudo_exec mv ttyd /usr/local/bin/; then
        printf "\033[31mFailed to move ttyd to /usr/local/bin\033[0m\n"
        exit 1
    fi
}

makeinstall() {
    detect_and_install

    # current_dir=$(pwd)
    code_dir=$(mktemp -d -t ttyd.XXXXXX)

    git clone https://github.com/tsl0922/ttyd.git "$code_dir"
    
    cd "$code_dir" || {
        printf "\033[31mFailed to clone %s\033[0m\n" "$code_dir"
        exit 1
    }

    mkdir build
    cd build
    cmake ..
    make
    sudo_exec make install

    cd ..
    rm -rf "$code_dir"
}

main() {
    if ! check_installed ttyd; then
        if [ -z "$IN_CHINA" ]; then
            check_in_china
        fi

        if [ $# -eq 0 ]; then
            download
        else
            makeinstall
        fi
    fi

    if ! check_installed ttyd; then
        printf "\033[31mFailed to install ttyd\033[0m\n"
        exit 1
    fi
}

main "$@"
