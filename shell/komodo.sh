#!/usr/bin/env bash

#============================================================
# File: komodo.sh
# Description: 
# URL: https://fx4.cn/komodo
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-12-10
# UpdatedAt: 2025-12-10
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
download_file() {
    local download_file="$1"
    local _download_url="$2"
    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi
}

settings() {
    cp ferretdb.compose.yaml compose.yml
    cp compose.env .env

    sed -i "s#./compose.env#./.env#g" compose.yml

    sed -i "s#Etc/UTC#Asia/Shanghai#g" .env

    PASSWORD=$(openssl rand -hex 8)
    sed -i "s#changeme#${PASSWORD}#g" .env
    echo "Password: $PASSWORD"
    
    KOMODO_WEBHOOK_SECRET=$(openssl rand -hex 16)
    sed -i "s#KOMODO_WEBHOOK_SECRET=.*#KOMODO_WEBHOOK_SECRET=${KOMODO_WEBHOOK_SECRET}#g" .env
    echo "KOMODO_WEBHOOK_SECRET: $KOMODO_WEBHOOK_SECRET"

    KOMODO_JWT_SECRET=$(openssl rand -hex 16)
    sed -i "s#KOMODO_JWT_SECRET=.*#KOMODO_JWT_SECRET=${KOMODO_JWT_SECRET}#g" .env
    echo "KOMODO_JWT_SECRET: $KOMODO_JWT_SECRET"
}

main() {
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")
        
    COMPOSE_FILE_URL="https://raw.githubusercontent.com/moghtech/komodo/main/compose/ferretdb.compose.yaml"
    ENV_FILE_URL="https://raw.githubusercontent.com/moghtech/komodo/main/compose/compose.env"

    COMPOSE_FILE_URL=$(do_remove_https "${CDN_URL}${COMPOSE_FILE_URL}")
    ENV_FILE_URL=$(do_remove_https "${CDN_URL}${ENV_FILE_URL}")

    download_file "ferretdb.compose.yaml" "$COMPOSE_FILE_URL"
    download_file "compose.env" "$ENV_FILE_URL"

    if [[ ! -f "ferretdb.compose.yaml" || ! -f "compose.env" ]]; then
        echo "Error: Failed to download ferretdb.compose.yaml or compose.env"
        exit 1
    fi

    settings
}

main "$@"
