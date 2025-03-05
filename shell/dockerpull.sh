#!/usr/bin/env bash

#============================================================
# File: dockerpull.sh
# Description: Docker 通过加速站拉取镜像
#
# ORIGIN: https://framagit.org/-/snippets/7412/raw/main/dockerpull.sh
#
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-02-22
# UpdatedAt: 2025-03-05
#============================================================

set -euo pipefail

# 默认镜像域名
DEFAULT_MIRROR_DOMAIN="${MIRROR:-dockerproxy.net}"

# 镜像名
IMAGE_NAME=""
# 加速站名
IMAGE_REGISTRY=""

# 源站服务镜像
IMAGE_URL=""
# 加速站服务镜像
IMAGE_MIRROR_URL=""

# 处理参数信息
judgment_parameters() {
    local HELP=""
    while [[ "$#" -gt '0' ]]; do
        case "$1" in

        '-i' | '--image')
            if [[ -z "${2:?error: Please specify the correct image name.}" ]]; then
                exit 1
            fi
            IMAGE_NAME="${2}"
            shift
            ;;

        '-r' | '--registry')
            if [[ -z "${2:?error: Please specify the correct registry name.}" ]]; then
                exit 1
            fi
            IMAGE_REGISTRY="${2}"
            shift
            ;;

        '-h' | '--help')
            HELP='1'
            break
            ;;

        *)
            echo "$0: unknown option -- $1"
            exit 1
            ;;

        esac
        shift
    done

    if [ -n "${HELP}" ]; then
        show_help
    fi
}

# 打印帮助信息
show_help() {
    echo "usage: $0 [ options ]"
    echo '  -i, --image    [IMAGE_NAME]          example: nginx:latest, my/nginx:latest'
    echo '  -r, --registry [REGISTRY_NAME]       options: d,docker | g,gcr | h,ghcr | k,k8s | q,quay | m,mcr'
    echo '  -h, --help                           print help'
    exit 0
}

# 处理加速站信息
select_registry() {
    case "${IMAGE_REGISTRY:-}" in
    'g' | 'gcr')
        IMAGE_URL="gcr.io/${IMAGE_NAME}"
        IMAGE_MIRROR_URL="gcr.${DEFAULT_MIRROR_DOMAIN}/${IMAGE_NAME}"
        ;;

    'h' | 'ghcr')
        IMAGE_URL="ghcr.io/${IMAGE_NAME}"
        IMAGE_MIRROR_URL="ghcr.${DEFAULT_MIRROR_DOMAIN}/${IMAGE_NAME}"
        # IMAGE_MIRROR_URL="ghcr.nju.edu.cn/${IMAGE_NAME}"
        ;;

    'k' | 'k8s')
        IMAGE_URL="registry.k8s.io/${IMAGE_NAME}"
        IMAGE_MIRROR_URL="k8s.${DEFAULT_MIRROR_DOMAIN}/${IMAGE_NAME}"
        ;;

    'q' | 'quay')
        IMAGE_URL="quay.io/${IMAGE_NAME}"
        IMAGE_MIRROR_URL="quay.${DEFAULT_MIRROR_DOMAIN}/${IMAGE_NAME}"
        ;;

    'm' | 'mcr')
        IMAGE_URL="mcr.microsoft.com/${IMAGE_NAME}"
        IMAGE_MIRROR_URL="mcr.${DEFAULT_MIRROR_DOMAIN}/${IMAGE_NAME}"
        ;;

    'd' | 'docker' | *)
        if echo "${IMAGE_NAME}" | grep -q "/"; then
            IMAGE_URL="${IMAGE_NAME}"
        else # 根镜像
            IMAGE_URL="library/${IMAGE_NAME}"
        fi
        IMAGE_MIRROR_URL="${DEFAULT_MIRROR_DOMAIN}/${IMAGE_URL}"
        ;;
    esac
}

# 显示信息
show_message() {
    echo "IMAGE_NAME: $IMAGE_NAME"
    echo "IMAGE_REGISTRY: $IMAGE_REGISTRY"
    echo "IMAGE_URL: $IMAGE_URL"
    echo "IMAGE_MIRROR_URL: $IMAGE_MIRROR_URL"
    echo
}

# 处理 URL
parsing_url() {
    url="${1:-}"

    # 根据第一个 . 前的字符串，获取需要取的容器
    case "${url%%/*}" in
    'gcr.io')
        IMAGE_REGISTRY="gcr"
        IMAGE_NAME="${url#*/}"
        ;;

    'ghcr.io')
        IMAGE_REGISTRY="ghcr"
        IMAGE_NAME="${url#*/}"
        ;;

    'registry.k8s.io')
        IMAGE_REGISTRY="k8s"
        IMAGE_NAME="${url#*/}"
        ;;

    'quay.io')
        IMAGE_REGISTRY="quay"
        IMAGE_NAME="${url#*/}"
        ;;

    'mcr.microsoft.com')
        IMAGE_REGISTRY="mcr"
        IMAGE_NAME="${url#*/}"
        ;;

    'docker.io')
        IMAGE_REGISTRY="docker"
        IMAGE_NAME="${url#*/}"
        ;;

    *)
        IMAGE_REGISTRY="docker"
        IMAGE_NAME="${url}"
        ;;
    esac
}

# 将加速站的 tag 重新打成镜像站的
progress_image() {
    docker pull "$IMAGE_MIRROR_URL"
    docker tag "$IMAGE_MIRROR_URL" "$IMAGE_URL"
    docker rmi "$IMAGE_MIRROR_URL"
}

# 判断是否为 docker compose 项目
is_docker_compose() {
    return "$(find . -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) | wc -l)"
}

main() {
    judgment_parameters "$@"

    echo "DEFULAT_DOMAIN: https://${DEFAULT_MIRROR_DOMAIN}/"
    echo

    if [ -n "${IMAGE_NAME}" ]; then
        # 若不存在 -r 参数，则判断 -i 是否为完整的 URL
        if [ -z "${IMAGE_REGISTRY}" ]; then
            parsing_url "${IMAGE_NAME}"
        fi

        select_registry

        show_message

        progress_image

        exit 0
    fi

    if is_docker_compose -eq 0; then
        echo "Not found .yml or .yaml file"
        exit 1
    fi

    # docker-compose 项目
    find . -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) -exec grep -h -E '^\s*image:' {} + | awk '{pos=index($0,":"); print substr($0,pos+1)}' | while read -r url; do
        if [ -z "${url}" ]; then
            continue
        fi

        # 镜像名
        IMAGE_NAME=""
        # 加速站名
        IMAGE_REGISTRY=""

        # 源站服务镜像
        IMAGE_URL=""
        # 加速站服务镜像
        IMAGE_MIRROR_URL=""

        echo
        echo "FULL_IMAGE: $url"

        parsing_url "${url}"

        select_registry

        show_message

        progress_image

        echo "-----------------------------------"
    done
}

#
# 1. 保存此代码到 dockerpull 文件
# 2. 给予此文件的可执行权限 chmod +x dockerpull
# 3. 拉取镜像
#   3.1 dockerpull # 从此目录下的 .yml 和 .yaml 文件中提取 image:xxx
#   3.2 dockerpull -i alpine:latest # 从官方镜像站
#   3.3 dockerpull -i xtls/xray-core:latest -r ghcr  # (docker,gcr,ghcr,k8s,quay,mcr) 从指定源的镜像站
#   3.4 dockerpull -i docker.io/idevsig/filetas:latest # 完整的 URL 自动判断从指定源的镜像站
