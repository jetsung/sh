#!/usr/bin/env bash

#============================================================
# File: x.sh
# Description: 替换脚本中的字符串为加速网址
# URL: https://s.fx4.cn/x
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.1
# CreatedAt: 2025-03-05
# UpdatedAt: 2025-09-12
#============================================================

if [[ -n "$DEBUG" ]]; then
    set -eux
else
    set -euo pipefail
fi

CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

# 判断是否为 URL 的函数
check_is_url() {
    local url="$1"
    # 正则表达式匹配 URL
    if [[ "$url" =~ ^https?://[^[:space:]]+ ]]; then
        return 0  # 是 URL
    else
        return 1  # 不是 URL
    fi
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

# 保持最末只有一个斜杠
keep_a_slash() {
    echo "$1" | sed -E 's#/*$#/#'
}

# 检查是否需要去掉第二个 https
remove_second_https() {
    # shellcheck disable=SC2001
    echo "$1" | sed 's|\(https://[^/]\+\)/https://|\1/|g'
}

replace_github() {
    echo "$1" | sed -e "s#https://github.com#//${CDN}https://github.com#g" \
       -e "s#https://api.github.com#//${CDN}https://api.github.com#g" \
       -e "s#https://gist.github.com#//${CDN}https://gist.github.com#g" \
       -e "s#https://raw.githubusercontent.com#//${CDN}https://raw.githubusercontent.com#g"
}

main() {
    NO_HTTPS=$(check_remove_https "$CDN_URL")

    CDN_URL=$(keep_a_slash "$CDN_URL")

    METHOD=""
    case "${1:-}" in
        g | github)
        METHOD="github"
        source_url="${2:-}"
        shift 2
        ;;

        *)
        source_url="${1:-}"
    esac

    if [[ -z "$source_url" ]]; then
        echo "Error: 请提供要替换的网址"
        exit 1
    fi

    # echo "nohttps: $NO_HTTPS"
    source_url=$(remove_second_https "${CDN_URL}${source_url}")
    # echo "source_url: $source_url"
    # echo ""

    source=$(curl -fsSL "$source_url")
    if [[ "$METHOD" = "github" ]]; then
        source_sh=$(replace_github "$source")
    else
        source_sh="${source//https:\/\//${CDN_URL}https://}"

    fi

    if [[ -n "$NO_HTTPS" ]]; then
        source_sh=$(remove_second_https "$source_sh")
    fi    
    
    echo "$source_sh"
}

main "$@"

###
# 本地使用示例
# ./shell/x.sh https://get.docker.com | bash
# CDN=https://fastfile.asfd.cn/ ./shell/x.sh https://get.docker.com | bash
# 
# 网络使用示例
# curl -L https://s.fx4.cn/x | bash -s -- https://get.docker.com | bash
# curl -L https://s.fx4.cn/x | CDN=https://fastfile.asfd.cn/ bash -s -- https://get.docker.com | bash
# 
# 先保存至本地再操作（适合交互式）
# curl -L https://s.fx4.cn/x | bash -s -- https://get.docker.com | tee /tmp/docker.sh
# bash /tmp/docker.sh
###