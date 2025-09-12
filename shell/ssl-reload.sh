#!/usr/bin/env bash

#============================================================
# File: ssl-reload.sh
# Description: 检查 SSL 证书是否在指定时间范围内更新，更新则重启服务
# URL: https://fx4.cn/ssl-reload
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.3.0
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
# - 使用 openssl 检查证书的申请时间（notBefore）是否在指定小时数内，
# - 如果有，则执行 restart_scripts/ 目录下所有 .sh 文件来重启服务。
# - 支持配置：脚本所在目录下的 config.sh 定义 CONF_DIR 和 CHECK_HOURS。
# - 支持 init 参数：设置随机凌晨0-8点的 cron 任务来运行本脚本（检查模式）。
# - 支持 --help 参数：显示帮助信息。

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 加载配置
load_config() {
    CONFIG_FILE="$SCRIPT_DIR/config.sh"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "CONF_DIR=/etc/angie/wildcard" > "$CONFIG_FILE"
        echo "CHECK_HOURS=24" >> "$CONFIG_FILE"
        echo "创建配置文件：$CONFIG_FILE 使用默认值"
        chmod 644 "$CONFIG_FILE"
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    : "${CONF_DIR:=/etc/angie/wildcard}"
    : "${CHECK_HOURS:=24}"
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
            mapfile -t certs < <(grep -oP 'ssl_certificate\s+\K[^;]+' "$conf_file")
            cert_paths+=("${certs[@]}")
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
    local check_seconds=$((CHECK_HOURS * 3600))  # 将小时转换为秒
    local check_time_ago=$((current_time - check_seconds))

    while IFS= read -r path; do
        if [ -f "$path" ]; then
            not_before=$(openssl x509 -in "$path" -noout -startdate | grep -oP 'notBefore=\K.*')
            if [ -n "$not_before" ]; then
                not_before_ts=$(date -d "$not_before" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_before" +%s 2>/dev/null)
                # shellcheck disable=SC2181
                if [ $? -eq 0 ] && [ "$not_before_ts" -gt "$check_time_ago" ]; then
                    need_restart=true
                    echo "证书 $path 在过去 $CHECK_HOURS 小时内申请（notBefore: $not_before）。" >&2
                    break
                fi
            else
                echo "警告：无法从 $path 获取 notBefore 时间。" >&2
            fi
        else
            echo "警告：证书文件 $path 不存在。" >&2
        fi
    done <<< "$unique_paths"
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
    script_path="$(basename "$0")"
    local random_hour=$((RANDOM % 8))  # 0-7
    local random_min=$((RANDOM % 60))  # 0-59
    local cron_file="/etc/cron.d/ssl_reload"

    echo "$random_min $random_hour * * * root cd $SCRIPT_DIR; bash $script_path" > "$cron_file"
    chmod 644 "$cron_file"
    echo "已设置 cron 任务：每天 $random_hour:$random_min 运行 $script_path (写入 $cron_file)"

    systemctl restart cron.service
}

# 显示帮助信息
show_help() {
    echo "Usage: $(basename "$0") [init] [--help]"
    echo ""
    echo "Description:"
    echo "  检查 SSL 证书是否在指定时间范围内（默认24小时）申请，如果是，则执行重启脚本。"
    echo ""
    echo "Options:"
    echo "  init     设置随机凌晨0-8点的 cron 任务来运行本脚本（检查模式）。"
    echo "  --help   显示此帮助信息。"
    echo ""
    echo "配置："
    echo "  在脚本目录下的 config.sh 中定义以下变量（直接赋值，无需 export）："
    echo "    CONF_DIR=/path/to/config/dir   # 配置文件目录（默认：/etc/angie/wildcard）"
    echo "    CHECK_HOURS=24                 # 检查证书更新的时间范围，单位为小时（默认：24）"
    echo "  如果 config.sh 不存在，将自动创建并写入默认值。"
    exit 0
}

# 主函数
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            init)
                setup_cron
                exit 0
                ;;
            --help)
                show_help
                ;;
            *)
                echo "未知参数: $1"
                show_help
                ;;
        esac
    done

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
        echo "没有在过去 $CHECK_HOURS 小时内申请的证书，无需重启服务。"
    fi
}

# 执行主函数
main "$@"

# if [[ "$(ps -ef | grep 'nginx: master' | grep -v "grep" | awk '{print $3}')" -eq 1 ]]; then
#     # 正在运行 nginx
#     if [ -f "/etc/init.d/nginx" ]; then
#         # bt
#         /etc/init.d/nginx stop
#         /etc/init.d/nginx start
#     else
#         # systemd
#         systemctl reload nginx
#     fi
    
#     echo -e "$(date -R) nginx reload"
# elif [[ "$(ps -ef | grep 'angie: master' | grep -v "grep" | awk '{print $3}')" -eq 1 ]]; then
#     # 正在运行 angie
#     systemctl reload angie
    
#     echo -e "$(date -R) angie reload"    
# fi
