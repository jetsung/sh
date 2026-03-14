#!/usr/bin/env bash

#============================================================
# File: komodo.sh
# Description: Komodo 一键安装脚本
# URL: https://fx4.cn/komodo
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.1
# CreatedAt: 2025-12-10
# UpdatedAt: 2026-03-14
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
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d <dir>       下载目录 (默认为: .)"
    echo "  -u <host>      Komodo 主机地址 (例如: komodo.example.com)"
    echo "  -r <dir>       Periphery 根目录 (PERIPHERY_ROOT_DIRECTORY)"
    echo "  -o             启用覆盖模式 (使用 compose.override.yaml)"
    echo "  -h             显示此帮助信息"
    echo ""
    exit 0
}

download_file() {
    local download_file="$1"
    local _download_url="$2"
    if ! curl -fsSL "$_download_url" -o "$download_file"; then
        echo "Error: Failed to download $download_file"
        exit 1
    fi
}

# 配置覆盖模式
settings_override() {
    echo

    {
        echo "TZ=Asia/Shanghai"
        echo "COMPOSE_KOMODO_IMAGE_TAG=${KOMODO_IMAGE_TAG}"
        if [[ -n "$KOMODO_HOST_VALUE" ]]; then
            echo "KOMODO_HOST=${KOMODO_HOST_VALUE}"
        fi
        
        echo "KOMODO_PASSKEY=$(openssl rand -hex 16)"
        echo "KOMODO_WEBHOOK_SECRET=$(openssl rand -hex 16)"
        echo "KOMODO_JWT_SECRET=$(openssl rand -hex 16)"
        echo "KOMODO_INIT_ADMIN_PASSWORD=$(openssl rand -hex 8)"

        if [[ -n "$PERIPHERY_ROOT_DIRECTORY" ]]; then
            echo "PERIPHERY_ROOT_DIRECTORY=$PERIPHERY_ROOT_DIRECTORY"
        fi        
    } > "${DOWNLOAD_DIR}/.env"

    echo
    cat "${DOWNLOAD_DIR}/.env"

    {
        echo "services:"
        echo "  core:"
        echo "    env_file: ./.env"
        echo ""
        echo "  periphery:"
        echo "    env_file: ./.env"        
    } > "${DOWNLOAD_DIR}/compose.override.yaml"

    {
        cat > "${DOWNLOAD_DIR}/deploy.sh" <<-'EOF'
#!/usr/bin/env bash

docker compose -p komodo -f ferretdb.compose.yaml -f compose.override.yaml --env-file compose.env --env-file .env $@

EOF
        sudo_exec chmod +x "${DOWNLOAD_DIR}/deploy.sh"
    }

    echo
    echo "docker compose -p komodo -f ferretdb.compose.yaml -f compose.override.yaml --env-file compose.env --env-file .env up -d"
    echo
    echo "./deploy.sh up -d"
    echo
}

# 新文件配置模式
# 在原文件的基础上修改
settings_newfile() {
    cp "${DOWNLOAD_DIR}/ferretdb.compose.yaml" "${DOWNLOAD_DIR}/compose.yml"
    cp "${DOWNLOAD_DIR}/compose.env" "${DOWNLOAD_DIR}/.env"

    sed -i "s#./compose.env#./.env#g" "${DOWNLOAD_DIR}/compose.yml"

    sed -i "s#Etc/UTC#Asia/Shanghai#g" "${DOWNLOAD_DIR}/.env"
    sed -i "s#^COMPOSE_KOMODO_IMAGE_TAG.*#COMPOSE_KOMODO_IMAGE_TAG=${KOMODO_IMAGE_TAG}#g" "${DOWNLOAD_DIR}/.env"

    echo
    
    if [[ -n "$KOMODO_HOST_VALUE" ]]; then
        # she-secure-online-storage-and-collaboration-in-the-workplace
        escaped_host=$(printf '%s\n' "$KOMODO_HOST_VALUE" | sed 's:[\\/&]:\\&:g')
        if grep -q "^KOMODO_HOST=" "${DOWNLOAD_DIR}/.env"; then
            sed -i "s#^KOMODO_HOST=.*#KOMODO_HOST=${escaped_host}#g" "${DOWNLOAD_DIR}/.env"
        else
            echo "KOMODO_HOST=${KOMODO_HOST_VALUE}" >> "${DOWNLOAD_DIR}/.env"
        fi
        echo "KOMODO_HOST: $KOMODO_HOST_VALUE"
    fi

    KOMODO_PASSKEY=$(openssl rand -hex 16)
    sed -i "s#^KOMODO_PASSKEY=.*#KOMODO_PASSKEY=${KOMODO_PASSKEY}#g" "${DOWNLOAD_DIR}/.env"
    echo "KOMODO_PASSKEY: $KOMODO_PASSKEY"

    KOMODO_WEBHOOK_SECRET=$(openssl rand -hex 16)
    sed -i "s#^KOMODO_WEBHOOK_SECRET=.*#KOMODO_WEBHOOK_SECRET=${KOMODO_WEBHOOK_SECRET}#g" "${DOWNLOAD_DIR}/.env"
    echo "KOMODO_WEBHOOK_SECRET: $KOMODO_WEBHOOK_SECRET"

    KOMODO_JWT_SECRET=$(openssl rand -hex 16)
    sed -i "s#^KOMODO_JWT_SECRET=.*#KOMODO_JWT_SECRET=${KOMODO_JWT_SECRET}#g" "${DOWNLOAD_DIR}/.env"
    echo "KOMODO_JWT_SECRET: $KOMODO_JWT_SECRET"

    if [[ -n "$PERIPHERY_ROOT_DIRECTORY" ]]; then
        sed -i "s#^PERIPHERY_ROOT_DIRECTORY=.*#PERIPHERY_ROOT_DIRECTORY=${PERIPHERY_ROOT_DIRECTORY}#g" "${DOWNLOAD_DIR}/.env"
        echo "PERIPHERY_ROOT_DIRECTORY: $PERIPHERY_ROOT_DIRECTORY"
    fi

    echo

    PASSWORD=$(openssl rand -hex 8)
    sed -i "s#changeme#${PASSWORD}#g" "${DOWNLOAD_DIR}/.env"
    echo "User: admin"
    echo "Password: $PASSWORD"
}

main() {
    DOWNLOAD_DIR="."
    KOMODO_HOST_VALUE=""
    OVERRIDE_SETTINGS=""
    PERIPHERY_ROOT_DIRECTORY=""
    KOMODO_IMAGE_TAG="dev"

    while getopts "t:d:u:r:oh" opt; do
        case ${opt} in
            t) KOMODO_IMAGE_TAG=$OPTARG;;
            d) DOWNLOAD_DIR=$OPTARG ;;
            u) KOMODO_HOST_VALUE=$OPTARG ;;
            r) PERIPHERY_ROOT_DIRECTORY=$OPTARG ;;
            o) OVERRIDE_SETTINGS="1" ;;
            h) usage ;;
            \?) usage ;;
            :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
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

    if [[ -n "$OVERRIDE_SETTINGS" ]]; then
        settings_override
        exit 0
    fi
    settings_newfile "$DOWNLOAD_DIR" "$KOMODO_HOST_VALUE"
}

main "$@"
