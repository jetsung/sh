#!/usr/bin/env bash

#============================================================
# File: rclone.sh
# Description: 安装 rclone 命令行工具
# URL: https://fx4.cn/rclone
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-19
# UpdatedAt: 2025-08-19
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

# rclone 官方仅提供 zip 包，且不支持 GitHub API 的 assets 命名匹配，
# 因此直接按官方 install.sh 的命名规则拼接下载地址。
get_download_url() {
    local channel="${1:-stable}"
    if [[ "$channel" == "beta" ]]; then
        echo "${CDN_URL}https://beta.rclone.org/rclone-beta-latest-${OS}-${OS_TYPE}.zip"
    else
        echo "${CDN_URL}https://downloads.rclone.org/rclone-current-${OS}-${OS_TYPE}.zip"
    fi
}

download_exact() {
    local download_file
    download_file="rclone.zip"
    TMP_DIR=$(mktemp -d /tmp/rclone.XXXXXX)

    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    if [[ -z "${CUSTOM_URL:-}" ]]; then
        _download_url=$(do_remove_https "${DOWNLOAD_URL}")
    else
        _download_url="$CUSTOM_URL"
    fi
    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi

    local unzip_tool=""
    for tool in unzip 7z busybox; do
        if check_is_command "$tool"; then
            unzip_tool="$tool"
            break
        fi
    done

    if [[ -z "$unzip_tool" ]]; then
        echo "Error: None of the supported unzip tools (unzip, 7z, busybox) were found."
        exit 1
    fi

    local unzip_dir="tmp_unzip_dir_for_rclone"
    mkdir -p "$unzip_dir"
    case "$unzip_tool" in
        'unzip')
            unzip -a "$download_file" -d "$unzip_dir"
            ;;
        '7z')
            7z x "$download_file" "-o$unzip_dir"
            ;;
        'busybox')
            busybox unzip "$download_file" -d "$unzip_dir"
            ;;
    esac

    pushd "$unzip_dir"/* >/dev/null

    # binary: 使用临时文件原子替换
    sudo_exec cp rclone /usr/bin/rclone.new
    sudo_exec chmod 755 /usr/bin/rclone.new
    sudo_exec chown root:root /usr/bin/rclone.new
    sudo_exec mv /usr/bin/rclone.new /usr/bin/rclone

    # manual
    if ! check_is_command "mandb"; then
        echo 'mandb not found. The rclone man docs will not be installed.'
    else
        sudo_exec mkdir -p /usr/local/share/man/man1
        sudo_exec cp rclone.1 /usr/local/share/man/man1/
        sudo_exec mandb
    fi

    popd >/dev/null
    popd >/dev/null
}

main() {
    # 解析命令行参数
    CUSTOM_URL=""
    CHANNEL="stable"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                CUSTOM_URL="$2"
                shift 2
                ;;
            --beta)
                CHANNEL="beta"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # 参数解析后处理 URL 环境变量
    if [[ -z "$CUSTOM_URL" && -n "${URL:-}" ]]; then
        CUSTOM_URL="$URL"
    fi

    # 优先级：命令行参数 > 环境变量 > 默认流程
    DOWNLOAD_URL="${CUSTOM_URL:-${URL:-}}"

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    OS_TYPE="$(uname -m)"

    case "$OS_TYPE" in
        x86_64|amd64)
            OS_TYPE='amd64'
            ;;
        i?86|x86)
            OS_TYPE='386'
            ;;
        aarch64|arm64)
            OS_TYPE='arm64'
            ;;
        armv7*)
            OS_TYPE='arm-v7'
            ;;
        armv6*)
            OS_TYPE='arm-v6'
            ;;
        arm*)
            OS_TYPE='arm'
            ;;
        *)
            echo "Unsupported arch: $OS_TYPE"
            exit 1
            ;;
    esac

    case "$OS" in
        linux)
            OS='linux'
            ;;
        darwin)
            OS='osx'
            ;;
        *)
            echo "Unsupported OS: $(uname)"
            exit 1
            ;;
    esac

    if [[ -z "$DOWNLOAD_URL" ]]; then

        if ! check_in_china; then
            CDN_URL=""
        fi

        NO_HTTPS=$(check_remove_https "$CDN_URL")

        DOWNLOAD_URL="$(get_download_url "$CHANNEL")"

        if [[ -z "$DOWNLOAD_URL" ]]; then
            echo "Error: Could not build a download URL for $OS-$OS_TYPE"
            exit 1
        fi
    else
        echo "使用指定下载地址: $DOWNLOAD_URL"
    fi

    download_exact

    echo ""

    if ! check_is_command "rclone"; then
        echo "rclone has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "rclone has been installed successfully!"
    echo ""
    rclone version
    echo ""
    rclone --help
    echo ""
}

main "$@"
