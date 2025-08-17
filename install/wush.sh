#!/usr/bin/env bash

#============================================================
# File: wush.sh
# Description: wush 网络穿透工具
# URL: https://s.fx4.cn/wush
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-14
# UpdatedAt: 2025-03-14
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
    curl -fsSL "$repo_api_url" | jq -r --arg arch "$ARCH" --arg os "$OS" --arg ext "$2" '.assets[] | select(.name | test("\($os)_\($arch).\($ext)")) | .browser_download_url'
}

get_system_info() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "deepin" ]]; then
            echo "debian"
        elif [[ "$ID" == "centos" || "$ID" == "fedora" || "$ID" == "redhat" ]]; then
            echo "redhat"
        else
            echo "unknown"
        fi
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    else
        echo "unknown"
    fi    
}

do_install() {
    case "${METHOD,,}" in
        "p" | "package")
            install_with_package
            ;;

        "b" | "binary")
            install_with_binary
            ;;
        
        "s" | "shell"  | *)
            install_with_shell
            ;;
    esac
}

install_with_package() {
    echo "Installing with package (${SYSTEM})..."

    local download_file="tmp"
    local file_bin="wush"
    TMP_DIR=$(mktemp -d /tmp/wush.XXXXXX)
    
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    local _pkg_ext=""
    if [[ "$SYSTEM" == "debian" ]]; then
        _pkg_ext="deb"
    elif [[ "$SYSTEM" == "redhat" ]]; then
        _pkg_ext="rpm"
    else
        echo "Unsupported system: $SYSTEM"
        exit 1
    fi

    _download_url=$(get_download_url "$REPO" "$_pkg_ext")
    _download_url=$(do_remove_https "${CDN_URL}${_download_url}") 

    local _pkg_file="${download_file}.${_pkg_ext}"

    if ! curl -fsSL "$_download_url" -o "$_pkg_file"; then
        echo "Error: Failed to download $_pkg_file"
        exit 1
    fi

    if [[ "$SYSTEM" == "debian" ]]; then
        sudo_exec dpkg -i "$_pkg_file"
    elif [[ "$SYSTEM" == "redhat" ]]; then
        sudo_exec rpm -i "$_pkg_file"
    fi

    popd >/dev/null
}

install_with_binary() {
    echo "Installing with binary (${SYSTEM} ${OS} ${ARCH} .tar.gz)..."

    local download_file="tmp.tar.gz"
    local file_bin="wush"
    TMP_DIR=$(mktemp -d /tmp/wush.XXXXXX)
    
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    _download_url=$(get_download_url "$REPO" "tar.gz")
    _download_url=$(do_remove_https "${CDN_URL}${_download_url}") 

    pushd "$TMP_DIR" >/dev/null

    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi

    if ! tar -xzf "$download_file"; then 
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi  

    sudo_exec mv "$file_bin" /usr/local/bin/

    popd >/dev/null    
}

install_with_shell() {
    echo "Installing with shell (${SYSTEM})..."

    local download_url="${CDN_URL}https://github.com/coder/wush/raw/refs/heads/main/install.sh"
    download_url=$(do_remove_https "$download_url") 
    curl -L "$download_url" | sudo_exec bash    
}

judgment_parameters() {
  while getopts "m:" opt; do
    case "$opt" in
      m)
        METHOD="$OPTARG"
        ;;

      \?)
        echo "Usage: $0 [-m <b|binary|p|package|s|shell>]"
        exit 1
        ;;
    esac
  done
}

main() {
    judgment_parameters "$@"

    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    REPO="coder/wush"
    SYSTEM="$(get_system_info)"

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    case "$ARCH" in
        "x86_64")
            ARCH="amd64"
            ;;
        "aarch64")
            ARCH="arm64"
            ;;
    esac

    METHOD="${METHOD:-b}"

    do_install

    echo ""

    if ! check_is_command "wush"; then
        echo "wush has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "wush has been installed successfully!"
    echo ""
    wush --help
    echo ""
    wush --version
    echo ""
}

main "$@"

###
# -m binary   二进制文件方式 (默认)
# -m package  deb/rpm 方式
# -m shell    官方脚本方式
