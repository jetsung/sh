#!/usr/bin/env bash

#============================================================
# File: delta.sh
# Description: 增强 git diff 的彩色显示工具
# URL: https://fx4.cn/delta
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-08-31
# UpdatedAt: 2026-08-31
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
    curl -fsSL "$repo_api_url" | jq -r --arg triple "$TRIPLE" '
        .assets[]
        | select(.name | endswith("-" + $triple + ".tar.gz"))
        | .browser_download_url
    '
}

download_exact() {
    local download_file="tmp.tar.gz"
    local file_bin="delta"
    TMP_DIR=$(mktemp -d /tmp/delta.XXXXXX)

    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    if [[ -z "${CUSTOM_URL:-}" ]]; then
        _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    else
        _download_url="$CUSTOM_URL"
    fi
    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi

    if ! tar -xzf "$download_file"; then
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi

    # 二进制可能在包根目录，也可能在子目录
    if [[ ! -f "$file_bin" ]]; then
        file_bin=$(find . -type f -name "delta" -print -quit)
        if [[ -z "$file_bin" ]]; then
            echo "Error: delta binary not found in package"
            exit 1
        fi
    fi

    chmod +x "$file_bin"
    sudo_exec mv "$file_bin" /usr/local/bin/delta

    popd >/dev/null
}

main() {
    CUSTOM_URL=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                CUSTOM_URL="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$CUSTOM_URL" && -n "${URL:-}" ]]; then
        CUSTOM_URL="$URL"
    fi

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"

    case "$OS-$ARCH" in
        linux-x86_64) TRIPLE="x86_64-unknown-linux-gnu" ;;
        linux-aarch64|linux-arm64) TRIPLE="aarch64-unknown-linux-gnu" ;;
        darwin-arm64) TRIPLE="aarch64-apple-darwin" ;;
        *)
            echo "Unsupported OS/ARCH: $OS-$ARCH"
            exit 1
            ;;
    esac

    if [[ -z "$CUSTOM_URL" ]]; then

        if ! check_in_china; then
            CDN_URL=""
        fi

        NO_HTTPS=$(check_remove_https "$CDN_URL")

        DOWNLOAD_URL="$(get_download_url dandavison/delta)"

        if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
            echo "Error: Could not find a download URL for $TRIPLE"
            exit 1
        fi
    else
        DOWNLOAD_URL=""
        echo "使用指定下载地址: $CUSTOM_URL"
    fi

    download_exact

    echo ""

    if ! check_is_command "delta"; then
        echo "delta has not been installed successfully."
        echo ""
        exit 1
    fi

    echo ""
    echo "delta has been installed successfully!"
    echo ""
    delta --version
    echo ""
    delta --help
    echo ""
}

main "$@"
