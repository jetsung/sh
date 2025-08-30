#!/usr/bin/env bash

#============================================================
# File: ssl-reload.sh
# Description: 检查 ssl 证书是否过期，过期则重启服务
# URL: https://s.fx4.cn/ssl-reload
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-30
# UpdatedAt: 2025-08-30
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 脚本功能：
# - 从可配置目录（如 /etc/angie/wildcard/*.conf）中提取 ssl_certificate 的路径，
# - 使用 openssl 检查证书的申请时间（notBefore）是否在过去24小时内，
# - 如果有，则执行 restart_scripts/ 目录下所有 .sh 文件来重启服务。
# - 支持配置：脚本所在目录下的 config.sh 定义 CONF_DIR。
# - 支持 init 参数：设置随机凌晨0-8点的 cron 任务来运行本脚本（检查模式）。

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 加载配置
load_config() {
    CONFIG_FILE="$SCRIPT_DIR/config.sh"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    else
        echo "错误：配置文件 $CONFIG_FILE 不存在。请创建它并定义 CONF_DIR。"
        exit 1
    fi
    : "${CONF_DIR:=/etc/angie/wildcard}"
}

# 创建重启脚本目录
setup_restart_dir() {
    RESTART_DIR="$SCRIPT_DIR/restart_scripts"
    if [ ! -d "$RESTART_DIR" ]; then
        mkdir -p "$RESTART_DIR"
        echo "创建重启脚本目录：$RESTART_DIR"
    fi
}

# 提取证书路径
extract_cert_paths() {
    local cert_paths=()
    for conf_file in "$CONF_DIR"/*.conf; do
        if [ -f "$conf_file" ]; then
            cert=$(grep -oP 'ssl_certificate\s+\K[^;]+' "$conf_file")
            if [ -n "$cert" ]; then
                cert_paths+=("$cert")
            fi
        fi
    done
    printf "%s\n" "${cert_paths[@]}" | sort -u
}

# 检查证书申请时间
check_certs() {
    local unique_paths="$1"
    local need_restart=false
    local current_time
    current_time=$(date +%s)
    local twenty_four_hours_ago=$((current_time - 86400))  # 24*3600=86400 秒

    for path in $unique_paths; do
        if [ -f "$path" ]; then
            not_before=$(openssl x509 -in "$path" -noout -startdate | grep -oP 'notBefore=\K.*')
            if [ -n "$not_before" ]; then
                not_before_ts=$(date -d "$not_before" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_before" +%s 2>/dev/null)
                # shellcheck disable=SC2181
                if [ $? -eq 0 ] && [ "$not_before_ts" -gt "$twenty_four_hours_ago" ]; then
                    need_restart=true
                    echo "证书 $path 在过去24小时内申请（notBefore: $not_before）。"
                    break
                fi
            else
                echo "警告：无法从 $path 获取 notBefore 时间。"
            fi
        else
            echo "警告：证书文件 $path 不存在。"
        fi
    done
    echo "$need_restart"
}

# 执行重启脚本
run_restart_scripts() {
    for script in "$RESTART_DIR"/*.sh; do
        if [ -f "$script" ]; then
            echo "执行 $script"
            if bash "$script"; then
                echo "$script 执行成功。"
            else
                echo "$script 执行失败。"
                exit 1
            fi
        fi
    done
}

# 设置 cron 任务
setup_cron() {
    local script_path
    script_path="$(realpath "$0")"
    local random_hour=$((RANDOM % 8))  # 0-7
    local random_min=$((RANDOM % 60))  # 0-59

    (crontab -l 2>/dev/null | grep -v "$script_path") | crontab -
    (crontab -l 2>/dev/null; echo "$random_min $random_hour * * * $script_path") | crontab -
    echo "已设置 cron 任务：每天 $random_hour:$random_min 运行 $script_path"
}

# 主函数
main() {
    if [ "${1:-}" = "init" ]; then
        setup_cron
        exit 0
    fi

    load_config
    setup_restart_dir
    local unique_paths
    unique_paths=$(extract_cert_paths)
    local need_restart
    need_restart=$(check_certs "$unique_paths")

    if [ "$need_restart" = true ]; then
        echo "检测到最近申请的证书，正在执行重启脚本..."
        run_restart_scripts
    else
        echo "没有在过去24小时内申请的证书，无需重启服务。"
    fi
}

# 执行主函数
main "$@"
