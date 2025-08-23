#!/usr/bin/env bash

#============================================================
# File: skopeo.sh
# Description: 镜像复制工具
# URL: https://s.fx4.cn/skopeo
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-18
# UpdatedAt: 2025-08-18
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
    if check_is_command "apt-get"; then
        echo "检测到 Debian/Ubuntu 系统，安装依赖..."
        sudo_exec apt-get update
        sudo_exec apt-get install -y git autoconf automake libtool gettext pkg-config libpng-dev libjpeg-dev
    elif check_is_command "dnf"; then
        echo "检测到 Fedora 系统，安装依赖..."
        sudo_exec dnf install -y git autoconf automake libtool gettext pkgconf libpng-devel libjpeg-turbo-devel
    elif check_is_command "yum"; then
        echo "检测到 CentOS/RHEL 系统，安装依赖..."
        sudo_exec yum install -y git autoconf automake libtool gettext pkgconf libpng-devel libjpeg-turbo-devel
    elif check_is_command "apk"; then
        echo "检测到 Alpine 系统，安装依赖..."
        sudo_exec apk add git autoconf automake libtool gettext-dev pkgconf libpng-dev jpeg-dev
    elif check_is_command "pacman"; then
        echo "检测到 Arch Linux 系统，安装依赖..."
        sudo_exec pacman -Syu --noconfirm --needed git autoconf automake libtool gettext pkgconf libpng libjpeg-turbo
    else
        echo "未检测到已知包管理器，请手动安装依赖：git autoconf automake libtool gettext pkgconf libpng libjpeg"
        return 1
    fi
}

clone_and_build() {
    TMP_DIR=$(mktemp -u "/tmp/skopeo.XXXX")

    cleanup() {
        rm -rf "$TMP_DIR"
    }
    trap cleanup EXIT

    _repo_url=$(do_remove_https "${CDN_URL}https://github.com/containers/skopeo.git")
    git clone "$_repo_url" "$TMP_DIR"
    pushd "$TMP_DIR" > /dev/null
    git fetch --tags
    git checkout "$(git tag --sort=-v:refname | head -n 1)"

    make bin/skopeo
    sudo_exec install -Dm755 bin/skopeo /usr/local/bin/skopeo
    popd > /dev/null
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    # 判断是否已安装 go 语言
    if ! check_is_command "go"; then
        echo "go must be installed."
        echo ""
        exit 1
    fi

    install_deps
    clone_and_build

    echo ""

    if ! check_is_command "skopeo"; then
        echo "skopeo has not been installed successfully."
        echo ""
        exit 1
    fi

    echo ""
    echo "skopeo has been installed successfully!"
    echo ""
    skopeo --help
    echo ""
    skopeo --version
    echo ""
}

main "$@"
