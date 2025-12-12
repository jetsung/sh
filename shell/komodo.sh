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
    local target_dir="$1"
    local komodo_host="$2"

    cp "${target_dir}/ferretdb.compose.yaml" "${target_dir}/compose.yml"
    cp "${target_dir}/compose.env" "${target_dir}/.env"

    sed -i "s#./compose.env#./.env#g" "${target_dir}/compose.yml"

    sed -i "s#Etc/UTC#Asia/Shanghai#g" "${target_dir}/.env"

    echo
    
    if [[ -n "$komodo_host" ]]; then
        # she-secure-online-storage-and-collaboration-in-the-workplace
        escaped_host=$(printf '%s\n' "$komodo_host" | sed 's:[\\/&]:\\&:g')
        if grep -q "^KOMODO_HOST=" "${target_dir}/.env"; then
            sed -i "s#^KOMODO_HOST=.*#KOMODO_HOST=${escaped_host}#g" "${target_dir}/.env"
        else
            echo "KOMODO_HOST=${komodo_host}" >> "${target_dir}/.env"
        fi
        echo "KOMODO_HOST: $komodo_host"
    fi

    KOMODO_PASSKEY=$(openssl rand -hex 16)
    sed -i "s#^KOMODO_PASSKEY=.*#KOMODO_PASSKEY=${KOMODO_PASSKEY}#g" "${target_dir}/.env"
    echo "KOMODO_PASSKEY: $KOMODO_PASSKEY"

    KOMODO_WEBHOOK_SECRET=$(openssl rand -hex 16)
    sed -i "s#^KOMODO_WEBHOOK_SECRET=.*#KOMODO_WEBHOOK_SECRET=${KOMODO_WEBHOOK_SECRET}#g" "${target_dir}/.env"
    echo "KOMODO_WEBHOOK_SECRET: $KOMODO_WEBHOOK_SECRET"

    KOMODO_JWT_SECRET=$(openssl rand -hex 16)
    sed -i "s#^KOMODO_JWT_SECRET=.*#KOMODO_JWT_SECRET=${KOMODO_JWT_SECRET}#g" "${target_dir}/.env"
    echo "KOMODO_JWT_SECRET: $KOMODO_JWT_SECRET"

    echo

    PASSWORD=$(openssl rand -hex 8)
    sed -i "s#changeme#${PASSWORD}#g" "${target_dir}/.env"
    echo "User: admin"
    echo "Password: $PASSWORD"
}

main() {
    DOWNLOAD_DIR="."
    KOMODO_HOST_VALUE=""

    while getopts "d:h:" opt; do
        case ${opt} in
            d) DOWNLOAD_DIR=$OPTARG ;;
            h) KOMODO_HOST_VALUE=$OPTARG ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
            :) echo "Invalid option: -$OPTARG requires an argument" >&2; exit 1;;
        esac
    done
    shift $((OPTIND -1))

    if [[ ! -d "$DOWNLOAD_DIR" ]]; then
        mkdir -p "$DOWNLOAD_DIR"
    fi

    if [[ -n "$KOMODO_HOST_VALUE" ]]; then
        if [[ ! "$KOMODO_HOST_VALUE" =~ ^https?:// ]]; then
            KOMODO_HOST_VALUE="http://$KOMODO_HOST_VALUE"
        fi
    fi
    
    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")
        
    COMPOSE_FILE_URL="https://raw.githubusercontent.com/moghtech/komodo/main/compose/ferretdb.compose.yaml"
    ENV_FILE_URL="https://raw.githubusercontent.com/moghtech/komodo/main/compose/compose.env"

    COMPOSE_FILE_URL=$(do_remove_https "${CDN_URL}${COMPOSE_FILE_URL}")
    ENV_FILE_URL=$(do_remove_https "${CDN_URL}${ENV_FILE_URL}")

    download_file "${DOWNLOAD_DIR}/ferretdb.compose.yaml" "$COMPOSE_FILE_URL"
    download_file "${DOWNLOAD_DIR}/compose.env" "$ENV_FILE_URL"

    if [[ ! -f "${DOWNLOAD_DIR}/ferretdb.compose.yaml" || ! -f "${DOWNLOAD_DIR}/compose.env" ]]; then
        echo "Error: Failed to download ferretdb.compose.yaml or compose.env"
        exit 1
    fi

    settings "$DOWNLOAD_DIR" "$KOMODO_HOST_VALUE"
}

main "$@"
