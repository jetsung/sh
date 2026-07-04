#!/usr/bin/env bash

#============================================================
# File: android-studio.sh
# Description: Android Studio
# URL: https://developer.android.com/studio
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2024-03-03
# UpdatedAt: 2024-03-03
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi


get_download_url() {
    local download_url
    download_url=$(curl -s 'https://developer.android.google.cn/studio?hl=zh-cn' | grep -o 'https://[^"]*linux\.tar\.gz')
    echo "$download_url"
}

install_android_studio() {
    local download_file="android-studio.tar.gz"
    TMP_DIR=$(mktemp -d /tmp/android-studio.XXXXXX)

    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    if [[ -z "$DOWNLOAD_URL" ]]; then
        DOWNLOAD_URL=$(get_download_url)
    else
        echo "使用指定下载地址: $DOWNLOAD_URL"
    fi
    echo "download_url: $DOWNLOAD_URL"

    if ! curl -fsSL "$DOWNLOAD_URL" -o "$download_file"; then
        echo "Error: Failed to download android-studio"
        exit 1
    fi

    local install_dir_path="$HOME/.local/"

    tar -xzf "$download_file" -C "$install_dir_path" || {
        echo "Failed to install android-studio."
        rm -f "$download_file"
        exit 1
    }

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

    install_android_studio

    export PATH="$HOME/.local/android-studio/bin:$PATH"

    echo ""
    echo "Android Studio has been installed successfully!"
    echo ""
    studio --help
    echo ""
    studio --version
    echo ""
}

main "$@"
