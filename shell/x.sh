#!/usr/bin/env bash

#============================================================
# File: x.sh
# Description: 替换脚本中的字符串为加速网址
# URL: https://fx4.cn/x
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.3
# CreatedAt: 2025-03-05
# UpdatedAt: 2026-03-26
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
    echo "$1" | sed -e "s#https://github.com#//${CDN_URL}https://github.com#g" \
       -e "s#https://api.github.com#//${CDN_URL}https://api.github.com#g" \
       -e "s#https://gist.github.com#//${CDN_URL}https://gist.github.com#g" \
       -e "s#https://raw.githubusercontent.com#//${CDN_URL}https://raw.githubusercontent.com#g"
}

main() {
    # 处理帮助选项
    case "${1:-}" in
        -h|--help)
            echo "Usage: x.sh [OPTIONS] [URL]"
            echo ""
            echo "替换脚本中的字符串为加速网址"
            echo ""
            echo "Options:"
            echo "  -h, --help     显示帮助信息"
            echo "  g, github     使用 GitHub 专用加速模式"
            echo ""
            echo "Environment Variables:"
            echo "  CDN            设置加速 CDN 地址 (默认: https://fastfile.asfd.cn/)"
            echo ""
            echo "Examples:"
            echo "  x.sh https://get.docker.com | bash"
            echo "  x.sh g https://get.docker.com | bash"
            echo "  CDN=https://cdn.example.com/ x.sh https://get.docker.com | bash"
            echo ""
            echo "URL: https://fx4.cn/x"
            exit 0
            ;;
    esac

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
    # source_url=$(remove_second_https "${CDN_URL}${source_url}")
    # echo "source_url: $source_url"
    # echo ""

    # 获取最终跳转后的 URL（如果没有跳转，curl 输出通常为空）
    final_url=$(curl -L -s -o /dev/null -w "%{url_effective}" --max-time 10 "$source_url" || true)

    # 关键修复：如果为空，就使用原始 URL
    if [[ -z "$final_url" ]] || [[ "$final_url" = "" ]]; then
        final_url="$source_url"
    fi

    source_url=$(remove_second_https "${CDN_URL}${final_url}")

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
# curl -L https://fx4.cn/x | bash -s -- https://get.docker.com | bash
# curl -L https://fx4.cn/x | CDN=https://fastfile.asfd.cn/ bash -s -- https://get.docker.com | bash
# 
# 先保存至本地再操作（适合交互式）
# curl -L https://fx4.cn/x | bash -s -- https://get.docker.com | tee /tmp/docker.sh
# bash /tmp/docker.sh
###