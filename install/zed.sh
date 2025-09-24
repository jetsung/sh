#!/usr/bin/env bash

#============================================================
# File: zed.sh
# Description: Zed 编辑器
# URL: https://fx4.cn/zed
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-17
# UpdatedAt: 2025-03-17
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
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${1}/releases")
    if [[ -z "${PRE_VERSION:-}" ]]; then
        repo_api_url="${repo_api_url}/latest"
    fi

    if [[ -n "${PRE_VERSION:-}" ]]; then
        curl -fsSL "$repo_api_url" | jq -r --arg package "$PACKAGE" '
        [ .[] | select(.prerelease == true) ]
        | first
        | .assets[]
        | select(.name | test($package; "i"))
        | .browser_download_url
        '
    else
        curl -fsSL "$repo_api_url" | jq -r --arg package "$PACKAGE" '
        .assets[] 
        | select(.name | test("\($package)"; "i")) 
        | .browser_download_url
        '
    fi    
}

download_exact() {
    if [[ "$OS" == "linux" ]]; then
        install_for_linux
    elif [[ "$OS" == "darwin" ]]; then
        install_for_macos
    else 
        echo "Unsupported OS: $OS"
        exit 1
    fi    
}

install_for_linux() {
    local download_file="tmp.tar.gz"
    local bin_path="zed${PRE_VERSION:+-preview}.app/bin/zed"
    TMP_DIR=$(mktemp -d /tmp/zed.XXXXXX)

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

    if [[ "$USER_ID" -eq 0 ]]; then
        _install_dir_path="/opt/"   
        _run_path="/usr/local/bin"   
    else
        _install_dir_path="$HOME/.local/"
        _run_path="$HOME/.local/bin"
    fi

    tar -xzf "$download_file" -C "$_install_dir_path" || {
        echo "Failed to install zed."
        rm -f "$download_file"
        exit 1
    }

    # 删除并重建软链接
    rm -rf "$_run_path/zed"
    ln -s "${_install_dir_path}${bin_path}" "$_run_path/zed"

    popd >/dev/null
}

install_for_macos() {
    local download_file="zed.dmg"    
    _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi

    echo ""
    echo "Save the DMG file to $download_file"
    echo "Download finished, please open the DMG file and drag Zed.app to your Applications folder."
    echo ""
    exit 0
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    # 预览版
    if [[ -n "${1:-}" && ("$1" = "-p" || "$1" = "--pre") ]]; then
        PRE_VERSION=1
    fi

    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"  
    PACKAGE=""  

    if [[ "$OS" == "darwin" ]]; then
        PACKAGE="Zed-${ARCH}.dmg"
    elif [[ "$OS" == "linux" ]]; then
        PACKAGE="zed-${OS}-${ARCH}.tar.gz"
    else
        echo "Unsupported OS: $OS"
        exit 1 
    fi

    DOWNLOAD_URL="$(get_download_url zed-industries/zed)"

    download_exact

    echo ""

    if ! check_is_command "zed"; then
        echo "zed has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "zed has been installed successfully!"
    echo ""
    zed --help
    echo ""
    zed --version
    echo ""    
}

main "$@"
