#!/usr/bin/env bash

#============================================================
# File: difftastic.sh
# Description: 能理解语法的结构化 diff 工具
# Source: https://github.com/Wilfred/difftastic
# URL: https://fx4.cn/difft
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-09-02
# UpdatedAt: 2026-09-02
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

# 从 GitHub releases 中按正则挑选安装包地址
get_download_url() {
    local repo="$1" os_re="$2" arch_re="$3"
    local repo_api_url
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${repo}/releases/latest")
    curl -fsSL "$repo_api_url" | jq -r --arg os "$os_re" --arg arch "$arch_re" '
        .assets[]?
        | select(.name | test("(?i)\\.(sha256|sha512|asc|sig|pem|json|txt|yaml|yml|deb|rpm|apk)$") | not)
        | select(.name | test($os; "i") and test($arch; "i"))
        | .browser_download_url
    ' | head -n 1
}

download_exact() {
    local file_bin="difft"
    local download_file="package.tar.gz"
    TMP_DIR=$(mktemp -d /tmp/difftastic.XXXXXX)

    # shellcheck disable=SC2329
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    local _download_url=""
    if [[ -n "${CUSTOM_URL:-}" ]]; then
        _download_url="$CUSTOM_URL"
    else
        _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    fi
    echo "下载地址: $_download_url"

    if ! curl -fL --retry 3 -o "$download_file" "$_download_url"; then
        echo "Error: Failed to download $_download_url"
        popd >/dev/null
        exit 1
    fi

    mkdir -p extract

    if ! tar -xzf "$download_file" -C extract; then
        echo "Error: Extraction failed"
        popd >/dev/null
        exit 1
    fi

    # 自动定位可执行文件：兼容「包内含顶层目录」与「包内直接是二进制」两种结构
    local _src=""
    if [[ -s raw_bin ]]; then
        _src="raw_bin"
    elif [[ -f "$file_bin" ]]; then
        _src="$file_bin"
    else
        _src=$(find extract -type f -name "$file_bin" 2>/dev/null | head -n 1)
    fi
    if [[ -z "$_src" ]]; then
        _src=$(find extract -type f -perm -u+x 2>/dev/null | head -n 1)
    fi
    if [[ -z "$_src" ]]; then
        echo "Error: 安装包中未找到可执行文件 ${file_bin}，包内文件列表如下："
        find extract -type f 2>/dev/null | head -n 40
        popd >/dev/null
        exit 1
    fi

    sudo_exec install -m 0755 "$_src" "/usr/local/bin/${file_bin}"

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
                echo "Usage: $0 [--url <download_url>]"
                exit 1
                ;;
        esac
    done

    if [[ -z "$CUSTOM_URL" && -n "${URL:-}" ]]; then
        CUSTOM_URL="$URL"
    fi

    # 优先级：命令行参数 > 环境变量 > 默认流程
    DOWNLOAD_URL="${CUSTOM_URL:-}"

    if [[ -z "$DOWNLOAD_URL" ]]; then
        if ! check_in_china; then
            CDN_URL=""
        fi

        NO_HTTPS=$(check_remove_https "$CDN_URL")

        OS="$(uname | tr '[:upper:]' '[:lower:]')"
        ARCH="$(uname -m)"

        OS_RE="$OS"
        case "$OS" in
            darwin) OS_RE="darwin|macos|osx|apple" ;;
        esac

        ARCH_RE="$ARCH"
        case "$ARCH" in
            x86_64|i686)   ARCH_RE="x86_64|amd64|x64" ;;
            aarch64|arm64) ARCH_RE="aarch64|arm64|armv8" ;;
            armv7l)        ARCH_RE="armv7|armhf" ;;
        esac

        DOWNLOAD_URL="$(get_download_url Wilfred/difftastic "$OS_RE" "$ARCH_RE")"

        if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
            echo "Error: 未在 Wilfred/difftastic 的最新 release 中找到匹配 $OS-$ARCH 的安装包"
            exit 1
        fi
    else
        echo "使用指定下载地址: $DOWNLOAD_URL"
    fi

    download_exact

    echo ""

    if ! check_is_command "difft"; then
        echo "difftastic has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "difftastic has been installed successfully!"
    echo ""
    difft --help || true
    echo ""
    difft --version || true
    echo ""
}

main "$@"
