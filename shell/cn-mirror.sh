#!/usr/bin/env bash

#============================================================
# File: os-mirror.sh
# Description: 中国镜像信息配置
# URL: https://fx4.cn/cnmirror
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-09-23
# UpdatedAt: 2025-09-23
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

#CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

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
# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case $ID in
            alpine)
                echo "alpine"
                ;;
            debian)
                echo "debian"
                ;;
            ubuntu)
                echo "ubuntu"
                ;;
            centos)
                echo "centos"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# 切换操作系统的镜像
switch_os() {
    system="$(detect_os)"
    if [[ "$system" == "unknown" ]]; then
        echo "os(${system}) mirror is unsupport."
        return 0
    fi

    if [[ "$system" == "debian" ]]; then
        apt_file="/etc/apt/sources.list"
        if [[ -f "/etc/apt/sources.list.d/debian.sources" ]]; then
            apt_file="/etc/apt/sources.list.d/debian.sources"
        fi
        sudo_exec sed -i.bak "s@http://deb.debian.org/@http://mirrors.aliyun.com/@g" "$apt_file"
        sudo_exec apt update -y
    elif [[ "$system" == "ubuntu" ]]; then
        apt_file="/etc/apt/sources.list"
        if [[ -f "/etc/apt/sources.list.d/ubuntu.sources" ]]; then
            apt_file="/etc/apt/sources.list.d/ubuntu.sources"
        fi
        if [[ -f "/etc/apt/sources.list.d/ports.list" ]]; then
            sudo_exec sed -i.bak "s@http://ports.ubuntu.com/@http://mirrors.aliyun.com/@g" "/etc/apt/sources.list.d/ports.list"
        fi
        sudo_exec sed -i.bak "s@http://archive.ubuntu.com/@http://mirrors.aliyun.com/@g" "$apt_file"
        sudo_exec sed -i.bak "s@http://security.ubuntu.com/@http://mirrors.aliyun.com/@g" "$apt_file"
        sudo_exec sed -i.bak "s@http://archive.archive.ubuntu.com/@http://mirrors.aliyun.com/@g" "$apt_file"        
        sudo_exec sed -i.bak "s@http://security.archive.ubuntu.com/@http://mirrors.aliyun.com/@g" "$apt_file"
        sudo_exec apt update -y
    elif [[ "$system" == "centos" ]]; then
        for repo_file in /etc/yum.repos.d/CentOS-*.repo; do
            sudo_exec sed -i.bak "s@^mirrorlist=@#mirrorlist=@g" "$repo_file"
            sudo_exec sed -i.bak "s@^#baseurl=http://mirror.centos.org@baseurl=http://mirrors.aliyun.com@g" "$repo_file"
        done
        sudo_exec yum update -y
    elif [[ "$system" == "alpine" ]]; then
        sudo_exec sed -i.bak 's@dl-cdn.alpinelinux.org@mirrors.aliyun.com@g' /etc/apk/repositories
        apk update
    fi
}

# 切换 UV（Python）
switch_uv() {
    if ! grep -q "UV_DEFAULT_INDEX" "$ENV_FILE"; then
        echo 'UV_DEFAULT_INDEX="https://mirrors.aliyun.com/pypi/simple/"' >> "$ENV_FILE"
    fi
    if ! grep -q "UV_EXTRA_INDEX" "$ENV_FILE"; then
        echo 'UV_EXTRA_INDEX="https://pypi.org/simple/"' >> "$ENV_FILE"
    fi
}

# 切换 PIP （Python）
switch_pip() {
    if ! grep -q "PIP_INDEX_URL" "$ENV_FILE"; then    
        echo 'PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"' >> "$ENV_FILE"
    fi
    if ! grep -q "PIP_EXTRA_INDEX_URL" "$ENV_FILE"; then    
        echo 'PIP_EXTRA_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"' >> "$ENV_FILE"
    fi
    if ! grep -q "PIP_TRUSTED_HOST" "$ENV_FILE"; then    
        echo 'PIP_TRUSTED_HOST="mirrors.aliyun.com"' >> "$ENV_FILE"
    fi
}

# 切换 NPM
switch_npm() {
    npm config set registry "https://registry.npmmirror.com"
}

main() {
    if [[ "${1:-}" = "-h" ]]; then
        echo "args:"
        echo "     os"
        echo "     uv"
        echo "     pip"
        echo "     npm"
    fi

    if ! check_in_china; then
    # if check_in_china; then
        echo "非中国网络，无需配置镜像源"
        exit 0
    fi

    ENV_FILE="/etc/environment"

    for env in "$@"; do
        if declare -f "switch_${env}" > /dev/null; then
            "switch_${env}"
        else
            printf "\n%s is unsupport.\n\n" "$env"
        fi
    done
}

main "$@"

###
#
# curl -L fx4.cn/osmirror | bash -s -- os
#
###