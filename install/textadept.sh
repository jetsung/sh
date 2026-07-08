#!/usr/bin/env bash

#============================================================
# File: textadept.sh
# Description: Textadept 编辑器
# URL: https://fx4.cn/textadept
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-05-03
# UpdatedAt: 2026-05-03
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

USER_ID="$(id -u)"

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
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${1}/releases")
    if [[ -z "${PRE_VERSION:-}" ]]; then
        repo_api_url="${repo_api_url}/latest"
    fi

    if [[ -n "${PRE_VERSION:-}" ]]; then
        curl -fsSL "$repo_api_url" | jq -r --arg package "$PACKAGE" '
        [ .[] | select(.prerelease == true) ]
        | first
        | .assets[]
        | select(.name | test($package; "i"))
        | .browser_download_url
        '
    else
        curl -fsSL "$repo_api_url" | jq -r --arg package "$PACKAGE" '
        .assets[]
        | select(.name | test("\($package)"; "i"))
        | .browser_download_url
        '
    fi
}

download_exact() {
    local download_file
    download_file="textadept.${ASSET_EXT}"
    TMP_DIR=$(mktemp -d /tmp/textadept.XXXXXX)

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

    local _sudo=""
    if [[ "$USER_ID" -ne 0 ]]; then
        _sudo="sudo"
    fi

    if [[ "$USER_ID" -eq 0 ]]; then
        _install_dir_path="/opt/"
        _bin_path="/usr/local/bin"
        _apps_path="/usr/share/applications"
    else
        _install_dir_path="$HOME/.local/"
        _bin_path="$HOME/.local/bin"
        _apps_path="$HOME/.local/share/applications"
    fi

    local install_dir="${_install_dir_path}textadept"

    $_sudo rm -rf "$install_dir"
    $_sudo mkdir -p "$install_dir"

    case "$ASSET_EXT" in
        tgz)
            if ! $_sudo tar -xzf "$download_file" -C "$install_dir" --strip-components=1; then
                echo "Error: Extraction failed"
                rm -f "$download_file"
                exit 1
            fi
            ;;
        zip)
            if ! $_sudo unzip -qo "$download_file" -d "$install_dir"; then
                echo "Error: Extraction failed"
                rm -f "$download_file"
                exit 1
            fi
            ;;
    esac

    $_sudo mkdir -p "$_bin_path"
    # 删除并重建软链接
    $_sudo ln -sf "${install_dir}/textadept" "${_bin_path}/textadept"
    $_sudo ln -sf "${install_dir}/textadept-gtk" "${_bin_path}/textadept-gtk"
    $_sudo ln -sf "${install_dir}/textadept-curses" "${_bin_path}/textadept-curses"

    # 需要根据不同的用户( root 或普通用户)，复制 ${install_dir}/textadept.desktop 到 applications 中
    if [[ -f "${install_dir}/textadept.desktop" ]]; then
        $_sudo mkdir -p "$_apps_path"
        $_sudo cp "${install_dir}/textadept.desktop" "${_apps_path}/textadept.desktop"
        # 修正 desktop 文件中的路径 (Exec 和 Icon)
        $_sudo sed -i "s|^Exec=.*|Exec=${_bin_path}/textadept %F|g" "${_apps_path}/textadept.desktop"
        $_sudo sed -i "s|^Icon=.*|Icon=${install_dir}/core/images/textadept.svg|g" "${_apps_path}/textadept.desktop"
    fi

    popd >/dev/null
}

main() {
    # 解析命令行参数
    CUSTOM_URL=""
    PRE_VERSION=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                CUSTOM_URL="$2"
                shift 2
                ;;
            -p|--pre)
                PRE_VERSION=1
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # 优先级：命令行参数 > 环境变量 > 默认流程
    DOWNLOAD_URL="${CUSTOM_URL:-${URL:-}}"

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"

    _OS="$OS"
    if [[ "$OS" == "darwin" ]]; then
        _OS="macOS"
    fi

    _ARCH="$ARCH"
    if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        _ARCH="arm"
    fi

    # 根据 OS 和 ARCH 确定资产匹配模式和扩展名
    ASSET_EXT=""
    PACKAGE=""
    case "${_OS}" in
        linux)
            ASSET_EXT="tgz"
            if [[ "$_ARCH" == "arm" ]]; then
                PACKAGE="linux\.arm\.tgz"
            else
                PACKAGE="linux\.tgz"
            fi
            ;;
        macOS)
            ASSET_EXT="zip"
            PACKAGE="macOS\.zip"
            ;;
        *)
            echo "Error: Unsupported OS: $_OS"
            exit 1
            ;;
    esac

    if [[ -z "$DOWNLOAD_URL" ]]; then

        if ! check_in_china; then
            CDN_URL=""
        fi

        NO_HTTPS=$(check_remove_https "$CDN_URL")

        DOWNLOAD_URL="$(get_download_url orbitalquark/textadept)"

        if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" || "$DOWNLOAD_URL" =~ ^[[:space:]]*$ ]]; then
            echo "Error: Could not find a download URL ($_OS-$_ARCH)"
            exit 1
        fi
    else
        echo "使用指定下载地址: $DOWNLOAD_URL"
    fi

    download_exact

    echo ""

    if ! check_is_command "textadept" && [[ ! -f "${_bin_path}/textadept" ]]; then
        echo "textadept has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "textadept has been installed successfully!"
    echo ""
    textadept-gtk --help
    echo ""
    textadept-gtk --version
    echo ""
}

main "$@"
