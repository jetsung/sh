#!/usr/bin/env bash

#============================================================
# File: ttyd.sh
# Description: 安装 ttyd
# URL: https://s.asfd.cn/
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-02-11
# UpdatedAt: 2025-03-07
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

is_command() {
    command -v "$1" >/dev/null 2>&1
}

is_in_china() {
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}

make_install() {
    code_dir=$(mktemp -d -t ttyd.XXXXXX)

    git clone "${CDN_URL}github.com/tsl0922/ttyd.git" "$code_dir"
    
    cd "$code_dir" || {
        printf "\033[31mFailed to clone %s\033[0m\n" "$code_dir"
        exit 1
    }

    mkdir build
    cd build
    cmake ..
    make
    sudo_exec make install

    cd ..
    rm -rf "$code_dir"
}

main() {
    if ! is_in_china; then
        CDN_URL=""
    fi

    make_install

    echo ""
    echo "ttyd has been installed successfully"
    echo ""
    echo "ttyd --version: $(frps --version)"
    echo "ttyd --version: $(frpc --version)"
    echo ""
}

main "$@"
