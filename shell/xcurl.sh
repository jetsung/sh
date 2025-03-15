#!/usr/bin/env bash

#============================================================
# File: xcurl.sh
# Description: 替换脚本中的字符串为加速网址
# URL:
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-05
# UpdatedAt: 2025-03-05
#============================================================

set -euo pipefail

# 判断是否为 URL 的函数
is_url() {
    local url="$1"
    # 正则表达式匹配 URL
    if [[ "$url" =~ ^https?://[^[:space:]]+ ]]; then
        return 0  # 是 URL
    else
        return 1  # 不是 URL
    fi
}

# 处理参数信息
judgment_parameters() {
    while [[ "$#" -gt '0' ]]; do
        case "${1,,}" in
            '-c' | '--cdn') 
            # CDN URL
                shift
                CDN="${1:?"错误: CDN 网址 (cdn) 不能为空."}"
                ;;
            '-p' | '--platform')
            # 平台
                shift
                PLATFORM="${1:?"错误: 平台 (platform) 不能为空."}"
                ;;


            '-h' | '--help')
                HELP=1
                ;;

            *)
                if [[ "$1" == -* ]]; then
                    echo "$0: 未知选项 -- $1" >&2
                    exit 1
                fi            
                FILE_PATH="${1:-}"
        esac
        shift
    done
}

replace_github() {
    sed -e "s#//github.com#//${CDN}/github.com#g" \
       -e "s#//api.github.com#//${CDN}/api.github.com#g" \
       -e "s#//raw.githubusercontent.com#//${CDN}/raw.githubusercontent.com#g" \
       "$OLD_FILE_PATH" > "$NEW_FILE_PATH"
}

show_help() {
    cat <<EOF
用法: $0 [options] [file|WEB_URL]

    替换脚本中的字符串为加速网址

$(help_common)
    -h,  --help                              打印帮助信息
    -c,  --cdn                               CDN 网址，默认为 fastfile.asfd.cn
    -p,  --platform       [github]           支持平台，默认为 github

EOF
    exit 0
}

main() {
    judgment_parameters "$@"

    if [ -n "${HELP:-}" ]; then
        show_help
    fi

    CDN="${CDN:-fastfile.asfd.cn}"
    PLATFORM="${PLATFORM:-github}"

    if [ -z "${FILE_PATH:-}" ]; then
        echo -e "\033[31m文件路径或网址不能为空.\033[0m"
        exit 1
    fi

    FILE_NAME=$(echo "$FILE_PATH" |sed 's#.*/\(.*\)#\1#' | awk -F'?' '{print $1}')
    OLD_FILE_PATH="/tmp/${FILE_NAME}.old.sh"
    NEW_FILE_PATH="/tmp/${FILE_NAME}.new.sh"

    if is_url "$FILE_PATH"; then
        wget -q -O "$OLD_FILE_PATH" "$FILE_PATH"
        IS_WEB=1
    elif [ -f "$FILE_PATH" ]; then
        cp "$FILE_PATH" "$OLD_FILE_PATH"
    else
        echo -e "\033[31m文件不存在.\033[0m"
        exit 1
    fi

    case "${PLATFORM:-}" in
        'github')
            replace_github
            ;;

        *)
            echo -e "\033[31m不支持的平台.\033[0m"
            exit 1
    esac

    cat "$NEW_FILE_PATH"
    
    if [ -z "${IS_WEB:-}" ]; then
        echo
        echo -e "\033[32m替换完成.\033[0m"
        echo  "新文件路径: $NEW_FILE_PATH"
    fi
        
}

main "$@"
