#!/usr/bin/env bash

# CloudflareSpeedTest
# https://github.com/XIU2/CloudflareSpeedTest
#

IN_CHINA=""
CF_DNS_FILE="cfdns"

CF_DOMAIN="222029.xyz"
CF_DOMAIN_PRE="cf"
CF_ZONE_TYPE="A"

GH_API_CDN="https://c.kkgo.cc"

init_os() {
    OS=$(uname | tr '[:upper:]' '[:lower:]')
    case "$OS" in
    darwin) OS='darwin' ;;
    linux) OS='linux' ;;
    freebsd) OS='freebsd' ;;
        #        mingw*) OS='windows';;
        #        msys*) OS='windows';;
    *)
        say_err "OS $OS is not supported by this installation script\n"
        ;;
    esac
}

init_arch() {
    ARCH=$(uname -m)

    case "$ARCH" in
    amd64) ARCH="amd64" ;;
    x86_64) ARCH="amd64" ;;
    i386) ARCH="386" ;;
    armv6l) ARCH="armv6l" ;;
    armv7l) ARCH="armv6l" ;;
    aarch64) ARCH="arm64" ;;
    *)
        say_err "Architecture $ARCH is not supported by this installation script\n"
        ;;
    esac
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

check_in_china() {
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
        IN_CHINA=1
    fi
}

get_latest_version() {
    repo=${1:-XIU2/CloudflareSpeedTest}

    latest_api_url="https://api.github.com/repos/$repo/releases/latest"
    if [ -n "$IN_CHINA" ]; then
        latest_api_url="${GH_API_CDN}/${latest_api_url//https:\/\/}"
    fi

    doanload_url=$(echo "$repo" | tr -d ' ' | xargs -I {} curl -s "$latest_api_url" | jq -r '.assets[].browser_download_url' | grep "${OS}_${ARCH}")
    if [ -z "$doanload_url" ]; then
        echo -e "\033[31mlatest version not found\033[0m"
        exit 1
    fi

    if [ -n "$IN_CHINA" ]; then 
        doanload_url="${GH_API_CDN}/${doanload_url//https:\/\/}"
    fi
    
    echo "$doanload_url"
}

check_installed() {
    init_arch
    init_os

    check_in_china
    download_url=$(get_latest_version "XIU2/CloudflareSpeedTest")

    # echo "download_url: $download_url"

    savedir=$(mktemp -d -t cfspeedtest.XXXXXX)
    packname=$(basename "$download_url")
    fullfilepath="$savedir/$packname"

    # echo "save to: $fullfilepath"
    curl -fsSL -o "$fullfilepath" "$download_url"

    pushd "$savedir" || {
        echo -e "\033[31mcd $savedir error\033[0m"
        exit 1
    }
        tar -zxf "$packname"
        filename="${packname//_*}"
        sudo mv "$filename" /usr/local/bin/cfspeedtest
    popd || exit 1    
}

refresh() {
    if ! check_command "cfspeedtest"; then
        check_installed
    fi

    if ! check_command "cfspeedtest"; then
        echo -e "\033[31mcfspeedtest not found\033[0m"
        exit 1
    fi

    if [ ! -f "ip.txt" ]; then
        curl -fsSL -o ip.txt https://www.cloudflare.com/ips-v4/
    fi

    cfspeedtest || {
        echo -e "\033[31mcfspeedtest install failed, please check the log\033[0m"
        exit 1
    }

    file_mtime=$(stat -c %y "" | cut -d' ' -f1)
}

refresh_dns() {
    if [ -z "${CLOUDFLARE_API_KEY:-}" ]; then
        echo -e "\033[31mCLOUDFLARE_API_KEY not found\033[0m"
        exit 1
    fi

    if [ -z "${CLOUDFLARE_EMAIL:-}" ]; then
        echo -e "\033[31mCLOUDFLARE_EMAIL not found\033[0m"
        exit 1
    fi

    file_mtime=$(stat -c %y "result.csv" | cut -d' ' -f1)
    if [ "$file_mtime" = "$today" ]; then
        index=0
        while IFS=, read -r ipv4 _ _ _ _ speed; do
            if (( $(echo "$speed < 100" | bc -l) )); then
                break
            fi
            # echo "$ipv4: $speed"
            ((index++))
            # echo "index: $index"
            "$CF_DNS_FILE" -a "$CLOUDFLARE_EMAIL" \
                -k "$CLOUDFLARE_API_KEY" \
                -ac set_record \
                -zn "$CF_DOMAIN" -rn "${CF_DOMAIN_PRE}${index}" -zy "$CF_ZONE_TYPE" -ct "$ipv4"
        done < <(tail -n +2 "result.csv")
    fi    

}

main() {
    file_mtime=$(stat -c %y "result.csv" | cut -d' ' -f1)
    today=$(date +%Y-%m-%d)

    if [ "$file_mtime" != "$today" ]; then
        refresh
    fi

    if check_command "$CF_DNS_FILE"; then
        refresh_dns
    fi
}

main "$@"