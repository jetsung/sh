#!/usr/bin/env bash

#============================================================
# 文件名: aliyunpan.sh
# 描述: 安装 aliyunpan
# URL: https://github.com/tickstep/aliyunpan
# 作者: Jetsung Chan <i@jetsung.com>
# 版本: 0.1.0
# 创建日期: 2025-03-05
# 更新日期: 2025-03-05
#============================================================

set -euo pipefail
# set -eux

REPO="tickstep/aliyunpan"

CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

USER_ID="$(id -u)"

sudo_exec() {
    if [[ "$USER_ID" -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

is_command() {
    command -v "$1" >/dev/null 2>&1
}

is_in_china() {
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}

get_arch() {
    uname -m | tr '[:upper:]' '[:lower:]'
}

get_os() {
    uname | tr '[:upper:]' '[:lower:]'
}

get_latest_release() {
    curl -sL "${CDN_URL}https://api.github.com/repos/${1}/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
}

get_download_url() {
    OS="$(get_os)"
    ARCH="$(get_arch)"
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    fi

    VERSION=$(get_latest_release "$REPO")
    download_url="${CDN_URL}https://github.com/${REPO}/releases/download/${VERSION}/aliyunpan-${VERSION}-${OS}-${ARCH}.zip"
    echo "$download_url"
}

main() {
    if ! is_in_china; then
        CDN_URL=""
    fi

    download_url=$(get_download_url)

    if ! curl -fsSL "$download_url" -o aliyunpan.zip; then
        printf "\033[31mFailed to download aliyunpan\033[0m\n"
        exit 1
    fi

    if ! unzip -q aliyunpan.zip; then
        printf "\033[31mFailed to extract aliyunpan\033[0m\n"
        exit 1
    fi

    mv "aliyunpan-"* aliyunpan

    if [[ -d "/opt/aliyunpan/" ]]; then
        sudo_exec rm -rf /opt/aliyunpan/
    fi

    if ! sudo_exec mv aliyunpan /opt/; then
        printf "\033[31mFailed to move aliyunpan to /opt\033[0m\n"
        exit 1
    fi

    if sudo_exec ln -sf /opt/aliyunpan/aliyunpan /usr/local/bin/aliyunpan; then
        echo ""
        aliyunpan --version
    else
        echo -e "\033[31maliyunpan install failed, Please Contact the author! \033[0m"
        kill -9 $$
    fi
    echo ""
}

main "$@"