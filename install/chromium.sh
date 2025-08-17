#!/usr/bin/env bash

#============================================================
# File: chromium.sh
# Description: Ungoogled Chromium
# URL: https://s.fx4.cn/chromium
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-10
# UpdatedAt: 2025-08-10
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
    curl -fsSL "$repo_api_url" | jq -r --arg os "$OS" --arg arch "$ARCH" '.assets[] | select(.name | test("\($arch)_\($os)")) | .browser_download_url'
}

download_exact() {
    local download_file="tmp.tar.xz"
    local file_bin="chrome"
    TMP_DIR=$(mktemp -d /tmp/chrome.XXXXXX)

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

    sudo_exec mkdir -p "$SAVE_DIR"
    if ! sudo_exec tar -xJf "$download_file" -C "$SAVE_DIR" --strip-components=1; then
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi

    popd >/dev/null

    # 若存在转链接则删除
    if [[ -f "/usr/local/bin/${file_bin}" ]]; then
        sudo_exec rm -f "/usr/local/bin/${file_bin}"
    fi

    # 添加软链接
    if ! sudo_exec ln -sf "${SAVE_DIR}/${file_bin}" "/usr/local/bin/${file_bin}"; then
        printf "\033[31mInstall %s failed, Please Contact the author! \033[0m" "$file_bin"
        kill -9 $$
    fi
}

set_desktop() {
    _desktop_file="$HOME/.local/share/applications/chromium.desktop"
    _icon_path="$SAVE_DIR/product_logo_48.png"

    cat > "$_desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Chromium
GenericName=Web Browser
Comment=Access the Internet
Exec=/usr/local/bin/chrome %U
Icon=$_icon_path
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;
EOF

    update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"

    DOWNLOAD_URL="$(get_download_url ungoogled-software/ungoogled-chromium-portablelinux)"
    SAVE_DIR="/opt/chromium"

    download_exact

    echo ""

    if ! check_is_command "chrome"; then
        echo "chrome has not been installed successfully."
        echo ""
        exit 1
    fi

    # 判断为桌面环境
    if [[ -n "$DISPLAY" ]] || [[ -n "$WAYLAND_DISPLAY" ]]; then
        set_desktop
    fi

    echo ""
    echo "chrome has been installed successfully!"
    echo ""
    chrome --version
    echo ""
}

main "$@"
