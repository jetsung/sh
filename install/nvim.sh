#!/usr/bin/env bash

#============================================================
# File: nvim.sh
# Description: Neovim 编辑器
# URL: https://fx4.cn/nvim
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.0
# CreatedAt: 2026-02-17
# UpdatedAt: 2026-04-29
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
    local version="${1:-latest}"
    local repo="neovim/neovim"
    local api_url
    
    if [[ "$version" == "latest" ]]; then
        api_url="${CDN_URL}https://api.github.com/repos/${repo}/releases/latest"
    else
        api_url="${CDN_URL}https://api.github.com/repos/${repo}/releases/tags/${version}"
    fi

    repo_api_url=$(do_remove_https "$api_url")
    curl -fsSL "$repo_api_url" | jq -r --arg arch "$_ARCH" --arg os "$_OS" '.assets[] | select(.name | test("nvim-\($os)-\($arch).tar.gz$")) | .browser_download_url'
}

download_exact() {
    local download_file="tmp.tar.gz"
    TMP_DIR=$(mktemp -d /tmp/nvim.XXXXXX)
    
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

    sudo_exec rm -rf "$INSTALL_DIR"
    sudo_exec mkdir -p "$INSTALL_DIR"
    
    if ! sudo_exec tar -xzf "$download_file" -C "$INSTALL_DIR" --strip-components=1; then 
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi  

    sudo_exec mkdir -p "$BIN_DIR"
    sudo_exec ln -sf "${INSTALL_DIR}/bin/nvim" "${BIN_DIR}/nvim"

    popd >/dev/null
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    
    _OS="$OS"
    if [[ "$OS" == "darwin" ]]; then
        _OS="macos"
    fi
    
    _ARCH="$ARCH"
    if [[ "$ARCH" == "aarch64" ]]; then
        _ARCH="arm64"
    fi

    # 统一使用全局安装路径
    INSTALL_DIR="/opt/nvim"   
    BIN_DIR="/usr/local/bin"   

    VERSION="${1:-${VERSION:-latest}}"
    DOWNLOAD_URL="$(get_download_url "$VERSION")"

    if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
        echo "Error: Could not find a download URL for version $VERSION ($_OS-$_ARCH)"
        exit 1
    fi

    download_exact

    echo ""

    if ! check_is_command "nvim" && [[ ! -f "${BIN_DIR}/nvim" ]]; then
        echo "nvim has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "nvim has been installed successfully!"
    echo ""
    nvim --help
    echo ""
    nvim --version
    echo
}

main "$@"
