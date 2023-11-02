#!/usr/bin/env bash

######
##
## 安装 docker-compose v2 (仅支持 Linux)
##
######

# Get OS bit
init_arch() {
    ARCH=$(uname -m)
    case $ARCH in
    amd64) ARCH="x86_64" ;;
    x86_64) ARCH="x86_64" ;;
    i386) ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    arm64) ARCH="aarch64" ;;
    armv6l) ARCH="armv6" ;;
    armv7l) ARCH="armv7" ;;
    *)
        printf "\e[1;31mArchitecture %s is not supported by this installation script\e[0m\n" "${ARCH}"
        exit 1
        ;;
    esac
}

# Get OS version
init_os() {
    OS=$(uname | tr '[:upper:]' '[:lower:]')
    if [[ "${OS}" != "linux" ]]; then
        printf "\e[1;31mOS %s is not supported by this installation script\e[0m\n" "${OS}"
        exit 1
    fi
}

# check in china
check_in_china() {
    urlstatus=$(curl -s -m 3 -IL https://google.com | grep 200)
    if [[ -z "${urlstatus}" ]]; then
        IN_CHINA=1
    fi
}

# get latest
get_latest_release() {
    curl --silent "https://api.github.com/repos/${1}/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' |                                            # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

main() {
    init_os

    init_arch

    check_in_china

    [[ -d "${HOME}/.docker/cli-plugins/" ]] || mkdir -p "${HOME}/.docker/cli-plugins/"

    case "${1}" in
    [1-9].[0-9].[0-9])
        VER="v${1}"
        echo 1
        ;;

    *)
        VER=$(get_latest_release docker/compose)
        ;;
    esac

    PROXY=""
    if [[ -n "${2}" ]]; then
        PROXY="${2}/"
    elif [[ -n "${IN_CHINA}" ]]; then
        PROXY="https://ghproxy.com/"
    fi

    printf "
ARCH: %s
VERSION: %s

PROXY: %s
\n" ${ARCH} "${VER}" "${PROXY}"

    curl -SL "${PROXY}https://github.com/docker/compose/releases/download/${VER}/docker-compose-${OS}-${ARCH}" \
        -o "${HOME}"/.docker/cli-plugins/docker-compose

    chmod +x "${HOME}"/.docker/cli-plugins/docker-compose

    docker compose version
}

main "$@" || exit 1
