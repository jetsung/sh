#!/usr/bin/env bash

#============================================================
# File: aliyunpan.sh
# Description: 安装 aliyunpan
# URL: https://s.asfd.cn/a21f20b9
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
    if [[ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]]; then
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
    echo "$1" | sed -E 's#/*$#/#'
}

# 检查是否需要去掉第二个 https
remove_second_https() {
    # shellcheck disable=SC2001
    echo "$1" | sed 's|\(https://[^/]\+\)/https://|\1/|g'
}

do_install() {
    repo_api_url="${CDN_URL}https://api.github.com/repos/tickstep/aliyunpan/releases/latest" 
    if [[ -n "$NO_HTTPS" ]]; then
        repo_api_url=$(remove_second_https "$repo_api_url")
    fi

    os_arch="${OS}-${ARCH}"
    download_url=$(curl -fsSL "$repo_api_url" | jq -r '.assets[].browser_download_url' | grep "$os_arch")

    filename_pkg="aliyunpan.zip"
    file_dir="aliyunpan"  

    download_url="${CDN_URL}${download_url}"
    if [[ -n "$NO_HTTPS" ]]; then
        download_url=$(remove_second_https "$download_url")
    fi

    if ! curl -fsSL "$download_url" -o "$filename_pkg"; then
        echo "Error: Failed to download $filename_pkg"
        exit 1
    fi

    if ! unzip -q -f "$filename_pkg"; then
        echo "Error: Extraction failed"
        rm -f "$filename_pkg"
        exit 1
    fi

    unzip -q "$filename_pkg"

    mv "${file_dir}-"* "$file_dir"

    if [[ -d "/opt/${file_dir}" ]]; then
        sudo_exec rm -rf /opt/"${file_dir}"
    fi

    if ! sudo_exec mv "$file_dir" /opt/; then
        printf "\033[31mFailed to move %s to /opt\033[0m\n" "$file_dir"
        exit 1
    fi

    # 若存在转链接则删除
    if [[ -f "/usr/local/bin/aliyunpan" ]]; then
        sudo_exec rm -f /usr/local/bin/aliyunpan
    fi

    if ! sudo_exec ln -sf "/opt/${file_dir}/aliyunpan" "/usr/local/bin/aliyunpan"; then
        printf "\033[31mInstall %s failed, Please Contact the author! \033[0m" "$file_dir"
        kill -9 $$
    fi

    rm -rf "$filename_pkg" 
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")
    CDN_URL=$(keep_a_slash "$CDN_URL")

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    fi    

    do_install

    echo ""

    if ! check_is_command "aliyunpan"; then
        echo "aliyunpan has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "aliyunpan has been installed successfully!"
    echo ""
    aliyunpan --version
    echo ""
}

main "$@"