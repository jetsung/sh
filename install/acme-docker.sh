#!/usr/bin/env bash

#============================================================
# File: acme-docker.sh
# Description: acme docker 方式脚本拉取
# URL: https://s.asfd.cn/a792ec34
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-05
# UpdatedAt: 2025-03-05
#============================================================

if [[ -n "$DEBUG" ]]; then
    set -eux
else
    set -euo pipefail
fi

REPO_RAW_URL="https://framagit.org/jetsung/docker-compose/-/raw/main/acme/"

install() {
    LIST=(
        .env
        docker-compose.yml
        docker-compose.override.yml
        README.md
        deploy.sh
    )

    for item in "${LIST[@]}"; do
        if [[ ! -f "$item" ]]; then
            curl -fsSL -O "${REPO_RAW_URL}${item}"
        fi
    done
}

main() {
    install || {
        echo -e "\033[31mInstall acme docker failed.\033[0m"
        exit 1
    }
    
    echo "Install success."
    echo ""
    ls -1
    echo ""

    chmod +x ./*.sh
    ./deploy.sh --help
}

main "$@"