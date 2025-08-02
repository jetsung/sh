#!/usr/bin/env bash

#============================================================
# File: aliyunpan.sh
# Description: 安装 aliyunpan
# URL: https://s.fx4.cn/aliyunpan
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-05
# UpdatedAt: 2025-03-25
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
    curl -fsSL "$repo_api_url" | jq -r --arg arch "$ARCH" --arg os "$OS" '.assets[] | select(.name | test("\($os)-\($arch)")) | .browser_download_url'
}

download_exact() {
    local download_file="tmp.tar.gz"
    local file_bin="aliyunpan"
    TMP_DIR=$(mktemp -d /tmp/aliyunpan.XXXXXX)
    
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

    if ! unzip -q -f "$download_file"; then
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi

    unzip -q "$download_file"

    mv "${file_bin}-"* "$file_bin"

    # 删除已存在的目录
    if [[ -d "/opt/${file_bin}" ]]; then
        sudo_exec rm -rf "/opt/${file_bin}"
    fi

    # 移动到目标目录
    if ! sudo_exec mv "$file_bin" /opt/; then
        printf "\033[31mFailed to move %s to /opt\033[0m\n" "$file_bin"
        exit 1
    fi

    popd >/dev/null

    # 若存在转链接则删除
    if [[ -f "/usr/local/bin/${file_bin}" ]]; then
        sudo_exec rm -f "/usr/local/bin/${file_bin}"
    fi

    # 添加软链接
    if ! sudo_exec ln -sf "/opt/${file_bin}/${file_bin}" "/usr/local/bin/${file_bin}"; then
        printf "\033[31mInstall %s failed, Please Contact the author! \033[0m" "$file_bin"
        kill -9 $$
    fi
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    fi    

    DOWNLOAD_URL="$(get_download_url tickstep/aliyunpan)"

    download_exact    

    echo ""

    if ! check_is_command "aliyunpan"; then
        echo "aliyunpan has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "aliyunpan has been installed successfully!"
    echo ""
    aliyunpan --help
    echo ""
    aliyunpan --version
    echo ""
}

main "$@"