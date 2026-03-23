#!/usr/bin/env bash

#============================================================
# File: ssl-check.sh
# Description: 检测 WebDAV 上的 SSL 证书是否在指定时间内更新，更新则执行升级和重启脚本
# URL: https://fx4.cn/sslcheck
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-03-24
# UpdatedAt: 2026-03-24
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 加载配置
load_config() {
    CONFIG_FILE="$SCRIPT_DIR/.env"
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
WEBDAV_USER=username
WEBDAV_PASS=password
WEBDAV_URL_TEMPLATE=https://dav.com/%s.fullchain.cer
DOMAINS=example.com,example.cn
CHECK_HOURS=48
CERTS_SAVE_DIR=certs
LOG_FILE=ssl-check.log
EOF
        echo "创建配置文件：$CONFIG_FILE 使用默认值"
        chmod 600 "$CONFIG_FILE"
    else
        # 如果文件存在但缺少 CERTS_SAVE_DIR，则追加
        if ! grep -q "CERTS_SAVE_DIR=" "$CONFIG_FILE"; then
            echo "CERTS_SAVE_DIR=certs" >> "$CONFIG_FILE"
            echo "已向 $CONFIG_FILE 追加默认 CERTS_SAVE_DIR=certs"
        fi
        # 如果文件存在但缺少 LOG_FILE，则追加
        if ! grep -q "LOG_FILE=" "$CONFIG_FILE"; then
            echo "LOG_FILE=ssl-check.log" >> "$CONFIG_FILE"
            echo "已向 $CONFIG_FILE 追加默认 LOG_FILE=ssl-check.log"
        fi
    fi
    
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    
    : "${WEBDAV_USER:=}"
    : "${WEBDAV_PASS:=}"
    : "${WEBDAV_URL_TEMPLATE:=}"
    : "${DOMAINS:=}"
    : "${CHECK_HOURS:=48}"
    : "${CERTS_SAVE_DIR:=certs}"
    : "${LOG_FILE:=ssl-check.log}"
    
    # 处理日志绝对路径
    if [[ "$LOG_FILE" == /* ]]; then
        ABS_LOG_FILE="$LOG_FILE"
    else
        ABS_LOG_FILE="$SCRIPT_DIR/$LOG_FILE"
    fi
}

# 日志记录函数
log() {
    local message="$1"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message"
    echo "[$timestamp] $message" >> "$ABS_LOG_FILE"
}

# 创建必要的目录
setup_dirs() {
    UPGRADE_DIR="$SCRIPT_DIR/upgrade_scripts"
    RESTART_DIR="$SCRIPT_DIR/restart_scripts"
    
    # 处理绝对路径和相对路径
    if [[ "$CERTS_SAVE_DIR" == /* ]]; then
        ABS_CERTS_SAVE_DIR="$CERTS_SAVE_DIR"
    else
        ABS_CERTS_SAVE_DIR="$SCRIPT_DIR/$CERTS_SAVE_DIR"
    fi
    
    mkdir -p "$UPGRADE_DIR"
    mkdir -p "$RESTART_DIR"
    mkdir -p "$ABS_CERTS_SAVE_DIR"
    
    # 创建 demo.sh 如果目录为空
    if [ ! -f "$UPGRADE_DIR/demo.sh" ]; then
        cat > "$UPGRADE_DIR/demo.sh" <<'EOF'
#!/usr/bin/env bash
# 示例升级脚本
DOMAIN=$1
# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# 加载 .env 获取 CERTS_SAVE_DIR
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi
: "${CERTS_SAVE_DIR:=certs}"

# 处理绝对路径和相对路径
if [[ "$CERTS_SAVE_DIR" == /* ]]; then
    ABS_CERTS_SAVE_DIR="$CERTS_SAVE_DIR"
else
    ABS_CERTS_SAVE_DIR="$SCRIPT_DIR/../$CERTS_SAVE_DIR"
fi

echo "正在处理域名: $DOMAIN"
echo "证书存储目录: $ABS_CERTS_SAVE_DIR"
echo "相关文件: "
ls -l "$ABS_CERTS_SAVE_DIR/$DOMAIN".*
EOF
        chmod +x "$UPGRADE_DIR/demo.sh"
    fi
}

# 下载证书文件
download_certs() {
    local domain="$1"
    local base_url
    # shellcheck disable=SC2059
    base_url=$(printf "$WEBDAV_URL_TEMPLATE" "$domain")
    
    local suffixes=(".fullchain.cer" ".ca.cer" ".key")
    
    log "开始下载 $domain 的证书文件到 $ABS_CERTS_SAVE_DIR ..."
    
    for suffix in "${suffixes[@]}"; do
        # 替换模板中的后缀 (假设模板以 .fullchain.cer 结尾)
        local url="${base_url/.fullchain.cer/$suffix}"
        local save_path="$ABS_CERTS_SAVE_DIR/$domain$suffix"
        
        if curl -s -f -u "$WEBDAV_USER:$WEBDAV_PASS" "$url" -o "$save_path"; then
            log "下载成功: $save_path"
        else
            log "下载失败: $url (可能是文件不存在)"
        fi
    done
}

# 检查单个域名的证书更新情况
check_domain_update() {
    local domain="$1"
    local url
    # shellcheck disable=SC2059
    url=$(printf "$WEBDAV_URL_TEMPLATE" "$domain")
    
    local current_time
    current_time=$(date +%s)
    local check_seconds=$((CHECK_HOURS * 3600))
    local check_time_ago=$((current_time - check_seconds))

    echo "正在检查域名: $domain ($url)" >&2
    
    # 获取证书内容并检查时间
    local cert_content
    if cert_content=$(curl -s -f -u "$WEBDAV_USER:$WEBDAV_PASS" "$url"); then
        not_before=$(echo "$cert_content" | openssl x509 -noout -startdate 2>/dev/null | grep -oP 'notBefore=\K.*' || true)
        
        if [ -n "$not_before" ]; then
            not_before_ts=$(date -d "$not_before" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_before" +%s 2>/dev/null)
            
            if [ -n "$not_before_ts" ] && [ "$not_before_ts" -gt "$check_time_ago" ]; then
                log "证书 $domain 在过去 $CHECK_HOURS 小时内更新过 (notBefore: $not_before)"
                return 0 # 有更新
            fi
        else
            echo "警告：无法从 $url 获取有效的证书信息" >&2
        fi
    else
        echo "错误：无法从 WebDAV 获取证书 $url" >&2
    fi
    
    return 1 # 无更新或失败
}

# 执行升级脚本
run_upgrade_scripts() {
    local domain="$1"
    for script in "$UPGRADE_DIR"/*.sh; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            log "执行升级脚本: $script $domain"
            if bash "$script" "$domain" >> "$ABS_LOG_FILE" 2>&1; then
                log "升级脚本 $script $domain 执行成功。"
            else
                log "错误：升级脚本 $script $domain 执行失败。"
            fi
        fi
    done
}

# 执行重启脚本
run_restart_scripts() {
    for script in "$RESTART_DIR"/*.sh; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            log "执行重启脚本: $script"
            if bash "$script" >> "$ABS_LOG_FILE" 2>&1; then
                log "重启脚本 $script 执行成功。"
            else
                log "错误：重启脚本 $script 执行失败。"
            fi
        fi
    done
}

# 设置 cron 任务
setup_cron() {
    local script_path
    script_path="$(basename "$0")"
    local random_hour=$((RANDOM % 8))
    local random_min=$((RANDOM % 60))
    local cron_file="/etc/cron.d/ssl_check"

    echo "$random_min $random_hour * * * root cd $SCRIPT_DIR; bash $script_path" > "$cron_file"
    chmod 644 "$cron_file"
    echo "已设置 cron 任务：每天 $random_hour:$random_min 运行 $script_path (写入 $cron_file)"
}

# 显示帮助
show_help() {
    echo "Usage: $(basename "$0") [init] [-h|--help]"
    echo ""
    echo "Description:"
    echo "  检查 WebDAV 上的 SSL 证书是否在 $CHECK_HOURS 小时内有更新。"
    echo "  如果有更新，则自动下载相关证书到中转站，触发 upgrade_scripts/ 下的脚本，"
    echo "  最后触发 restart_scripts/ 下的重启脚本。"
    echo ""
    echo "Options:"
    echo "  init         设置随机凌晨 0-8 点的 cron 任务并初始化目录与配置。"
    echo "  -h, --help   显示此帮助信息。"
    echo ""
    echo "配置文件: $SCRIPT_DIR/.env"
    echo ""
    echo "支持的配置变量："
    echo "  WEBDAV_USER          WebDAV 用户名"
    echo "  WEBDAV_PASS          WebDAV 密码"
    echo "  WEBDAV_URL_TEMPLATE  URL 模板，例如 https://dav.com/%s.fullchain.cer"
    echo "  DOMAINS              域名列表，逗号分隔"
    echo "  CHECK_HOURS          检查更新的时间范围（小时），默认 48"
    echo "  CERTS_SAVE_DIR       证书本地存储目录名，默认 certs"
    echo "  LOG_FILE             日志文件名，默认 ssl-check.log"
    exit 0
}

# 主逻辑
main() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            init)
                load_config
                setup_dirs
                setup_cron
                exit 0
                ;;
            -h|--help)
                load_config
                show_help
                ;;
            *)
                echo "未知参数: $1"
                load_config
                show_help
                ;;
        esac
    fi

    load_config
    setup_dirs
    
    if [ -z "$DOMAINS" ]; then
        echo "错误：未在 .env 中配置 DOMAINS"
        exit 1
    fi

    local restart_needed=false
    IFS=',' read -r -a domain_array <<< "$DOMAINS"
    
    for domain in "${domain_array[@]}"; do
        domain=$(echo "$domain" | xargs) # 去除空格
        if [ -n "$domain" ]; then
            if check_domain_update "$domain"; then
                download_certs "$domain"
                run_upgrade_scripts "$domain"
                restart_needed=true
            fi
        fi
    done

    if [ "$restart_needed" = true ]; then
        echo "检测到证书更新，正在执行服务重启逻辑..."
        run_restart_scripts
    else
        echo "所有域名证书在过去 $CHECK_HOURS 小时内均无更新。"
    fi
}

main "$@"
