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

    DOWNLOAD_URL=$(get_download_url)
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
