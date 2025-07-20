#!/usr/bin/env bash

#============================================================
# File: hugo.sh
# Description: 安装 hugo
# URL: https://s.fx4.cn/iuyTvo
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-07-20
# UpdatedAt: 2025-07-20
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

is_command() {
    command -v "$1" >/dev/null 2>&1
}

is_in_china() {
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
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

# 保持最末只有一个斜杠
keep_a_slash() {
    if [[ -n "$1" ]]; then
        echo "$1" | sed -E 's#/*$#/#'
    fi
}

# 检查是否需要去掉第二个 https
remove_second_https() {
    # shellcheck disable=SC2001
    echo "$1" | sed 's|\(https://[^/]\+\)/https://|\1/|g'
}

get_download_url() {
    repo_api_url="${CDN_URL}https://api.github.com/repos/gohugoio/hugo/releases/latest" 
    if [[ -n "$NO_HTTPS" ]]; then
        repo_api_url=$(remove_second_https "$repo_api_url")
    fi    
    curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "${OS}-${ARCH}.tar.gz" | grep -E "${PKG_PREFIX}_[0-9.]+"
}

download_exact() {
    DOWNLOAD_FILE="hugo.tar.gz"
    FILE_BIN="hugo"

    if ! curl -fsSL "${CDN_URL}${DOWNLOAD_URL}" -o "$DOWNLOAD_FILE"; then
        echo "Error: Failed to download $DOWNLOAD_FILE"
        exit 1
    fi

    if ! tar -xzf "$DOWNLOAD_FILE"; then 
        echo "Error: Extraction failed"
        rm -f "$DOWNLOAD_FILE"
        exit 1
    fi

    sudo_exec mv "$FILE_BIN" /usr/local/bin/

    rm -rf "$DOWNLOAD_FILE" LICENSE README.md
}

main() {
    if ! is_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")
    CDN_URL=$(keep_a_slash "$CDN_URL")    

    PKG_PREFIX="hugo"

    # 扩展版
    if [[ -n "${1:-}" ]]; then
        if [[ "$1" = "-w" || "$1" = "--ew" ]]; then
            PKG_PREFIX="${PKG_PREFIX}_extended_withdeploy"
        else
            PKG_PREFIX="${PKG_PREFIX}_extended"
        fi
    fi    

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
        x86_64) 
            ARCH="amd64" 
            ;;
        aarch64) 
            ARCH="arm64" 
            ;;
        *) 
            echo "Unsupported architecture"
            exit 1
            ;; 
    esac

    DOWNLOAD_URL="$(get_download_url)"

    download_exact

    echo ""
    echo "hugo has been installed successfully!"
    echo ""
    hugo version
    echo ""
}

main "$@"

# 基础版: curl -L https://s.fx4.cn/iuyTvo | bash
# 扩展版: curl -L https://s.fx4.cn/iuyTvo | bash -s -- -e
# 扩展版+部署: curl -L https://s.fx4.cn/iuyTvo | bash -s -- -w