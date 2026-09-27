#!/usr/bin/env bash

#============================================================
# File: deveco.sh
# Description: DevEco Code for Linux，AtomGit 上的 AI 编程智能体终端工具
# Source: https://atomgit.com/jetsung/deveco-linux
# URL: https://fx4.cn/deveco
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-09-27
# UpdatedAt: 2026-09-27
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

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

########################## 以上为通用函数 #########################

ATOMGIT_API="https://atomgit.com/api/v5/repos/jetsung/deveco-linux/releases"

get_download_url() {
    # 取最新 release 中 type 为 attach 的二进制附件（排除源码包）
    curl -fsSL "${ATOMGIT_API}?per_page=1" \
        | jq -r '.[0].assets[] | select(.type == "attach") | .browser_download_url' \
        | head -n 1
}

download_exact() {
    local download_file="tmp.tar.xz"
    local file_bin="deveco"
    TMP_DIR=$(mktemp -d /tmp/deveco.XXXXXX)

    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    if ! curl -fsSL "$DOWNLOAD_URL" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi

    if ! tar -xJf "$download_file"; then
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi

    local bin_path=""
    if [[ -f "$file_bin" ]]; then
        bin_path="$file_bin"
    elif [[ -f "raw_bin" ]]; then
        bin_path="raw_bin"
    else
        bin_path="$(find . -type f -name "$file_bin" | head -n 1)"
    fi

    if [[ -z "$bin_path" ]]; then
        echo "Error: Could not locate binary '$file_bin' in archive"
        tar -tf "$download_file"
        exit 1
    fi

    sudo_exec install -m 0755 "$bin_path" "/usr/local/bin/${file_bin}"

    popd >/dev/null
}

main() {
    # 解析命令行参数
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

    # 优先级：命令行参数 > 环境变量 > 默认流程
    DOWNLOAD_URL="${CUSTOM_URL:-${URL:-}}"

    if [[ -z "$DOWNLOAD_URL" ]]; then
        DOWNLOAD_URL="$(get_download_url)"

        if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
            echo "Error: Could not find a download URL from AtomGit release"
            exit 1
        fi
    else
        echo "使用指定下载地址: $DOWNLOAD_URL"
    fi

    download_exact

    echo ""

    if ! check_is_command "deveco"; then
        echo "deveco has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "deveco has been installed successfully!"
    echo ""
    deveco --version
    echo ""
}

main "$@"
