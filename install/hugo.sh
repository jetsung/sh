#!/usr/bin/env bash

#============================================================
# File: hugo.sh
# Description: 静态网站生成器
# URL: https://fx4.cn/hugo
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
    local version="${2:-}"
    if [[ -n "$version" ]]; then
        # Ensure version starts with v
        if [[ "$version" != v* ]]; then
            version="v$version"
        fi
        repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${1}/releases/tags/${version}")
    else
        repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${1}/releases/latest")
    fi
    
    curl -fsSL "$repo_api_url" | jq -r --arg arch "$ARCH" --arg os "$OS" '.assets[] | select(.name | test("\($os)-\($arch).tar.gz")) | .browser_download_url' | grep -E "${PKG_PREFIX}_[0-9.]+"
}

download_exact() {
    local download_file="tmp.tar.gz"
    local file_bin="hugo"
    TMP_DIR=$(mktemp -d /tmp/hugo.XXXXXX)
    
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    echo "Downloading: $_download_url"
    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi

    if ! tar -xzf "$download_file"; then 
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi  

    sudo_exec mv "$file_bin" /usr/local/bin/

    popd >/dev/null
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    PKG_PREFIX="hugo"
    VERSION=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -e|--extended)
                PKG_PREFIX="${PKG_PREFIX}_extended"
                shift
                ;;
            -w|--ew)
                PKG_PREFIX="${PKG_PREFIX}_extended_withdeploy"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [-v <version>] [-e] [-w]"
                echo "  -v, --version <version>  Specify the version to install (e.g. 0.115.4)"
                echo "  -e, --extended           Install extended edition"
                echo "  -w, --ew                 Install extended edition with deploy"
                echo "  -h, --help               Show this help message"
                exit 0
                ;;
            *)
                # Backward compatibility for positional args implies extended
                # If first arg is not a flag, assume it's requesting extended (old behavior)
                # But since we are looping, this might catch arguments to flags if not careful.
                # The old script just checked $1.
                if [[ "$1" == "-"* ]]; then
                    echo "Unknown option: $1"
                    exit 1
                else
                     PKG_PREFIX="${PKG_PREFIX}_extended"
                fi
                shift
                ;;
        esac
    done

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

    DOWNLOAD_URL="$(get_download_url gohugoio/hugo "$VERSION")"

    if [[ -z "$DOWNLOAD_URL" ]]; then
        echo "Error: Could not find download URL for version '${VERSION:-latest}'."
        exit 1
    fi

    download_exact

    echo ""

    if ! check_is_command "hugo"; then
        echo "hugo has not been installed successfully."
        echo ""
        exit 1
    fi

    echo ""
    echo "hugo has been installed successfully!"
    echo ""
    hugo help
    echo ""
    hugo version
    echo ""
}

main "$@"

# 基础版: curl -L https://fx4.cn/iuyTvo | bash
# 扩展版: curl -L https://fx4.cn/iuyTvo | bash -s -- -e
# 扩展版+部署: curl -L https://fx4.cn/iuyTvo | bash -s -- -w
