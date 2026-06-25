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
CONFIG_FILE="$SCRIPT_DIR/.env"
CRON_TAG="# ssl-check-managed"

init_env() {
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Environment file already exists: $CONFIG_FILE"
        read -r -p "Do you want to overwrite it? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    cat > "$CONFIG_FILE" << 'EOF'
# WebDAV Configuration
# ===================

# WebDAV credentials
WEBDAV_USER=username
WEBDAV_PASS=password

# URL template for certificate files
# Use %s as domain placeholder
# Example: https://dav.com/%s.fullchain.cer
WEBDAV_URL_TEMPLATE=https://dav.com/%s.fullchain.cer

# Domain Configuration
# ====================

# Domain list (comma-separated)
DOMAINS=example.com,example.cn

# Check time range in hours (default: 48)
CHECK_HOURS=48

# Storage Configuration
# =====================

# Local directory for certificates
CERTS_SAVE_DIR=certs

# Log file (relative to script dir or absolute path)
LOG_FILE=ssl-check.log

# Local mode: check local certificates only (skip WebDAV)
# Set to true if certificates are already downloaded locally
LOCAL_MODE=false

EOF

    chmod 600 "$CONFIG_FILE"
    echo "Environment file created: $CONFIG_FILE"
    echo "Please edit it with your WebDAV configuration."
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Warning: Environment file not found: $CONFIG_FILE" >&2
        echo "Use '$(basename "$0") init' to create one." >&2
        return 1
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
    : "${LOCAL_MODE:=false}"

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

    : "${CERTS_SAVE_DIR:=certs}"

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
    if [ "${LOCAL_MODE:-false}" = "true" ]; then
        log "本地模式，跳过从 webdav 下载证书"
        return 0
    fi

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
    
    local current_time
    current_time=$(date +%s)
    local check_seconds=$((CHECK_HOURS * 3600))
    local check_time_ago=$((current_time - check_seconds))

    if [ "${LOCAL_MODE:-false}" = "true" ]; then
        local cert_path="$ABS_CERTS_SAVE_DIR/$domain.fullchain.cer"
        echo "正在检查本地域名: $domain ($cert_path)" >&2
        
        if [ -f "$cert_path" ]; then
            not_before=$(openssl x509 -in "$cert_path" -noout -startdate 2>/dev/null | grep -oP 'notBefore=\K.*' || true)
            
            if [ -n "$not_before" ]; then
                not_before_ts=$(date -d "$not_before" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_before" +%s 2>/dev/null)
                
                if [ -n "$not_before_ts" ] && [ "$not_before_ts" -gt "$check_time_ago" ]; then
                    log "本地证书 $domain 在过去 $CHECK_HOURS 小时内更新过 (notBefore: $not_before)"
                    return 0 # 有更新
                fi
            else
                echo "警告：无法从 $cert_path 获取有效的证书信息" >&2
            fi
        else
            echo "错误：本地证书文件不存在 $cert_path" >&2
        fi
        
        return 1
    fi

    local url
    # shellcheck disable=SC2059
    url=$(printf "$WEBDAV_URL_TEMPLATE" "$domain")

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

cron_add() {
    local schedule="" domains="" check_hours="" local_mode="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domains) domains="$2"; shift 2 ;;
            -c|--check-hours) check_hours="$2"; shift 2 ;;
            --local) local_mode="true"; shift ;;
            *)
                if [[ -z "$schedule" ]]; then
                    schedule="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$schedule" ]]; then
        echo "Error: Schedule is required." >&2
        echo "Usage: $(basename "$0") cron add \"0 2 * * *\"" >&2
        exit 1
    fi

    load_config

    local cron_cmd
    local script_path
    script_path="${SCRIPT_DIR}/$(basename "$0")"

    if [[ "$schedule" == "random" ]]; then
        local random_hour=$((RANDOM % 8))
        local random_min=$((RANDOM % 60))
        cron_cmd="$random_min $random_hour * * * $script_path check"
    else
        local fields
        fields=$(echo "$schedule" | awk '{print NF}')
        if [[ "$fields" -lt 5 ]]; then
            echo "Error: Invalid cron schedule format." >&2
            echo "Expected 5 fields: minute hour day month weekday" >&2
            exit 1
        fi
        cron_cmd="$schedule $script_path check"
    fi

    [[ -n "$domains" ]] && cron_cmd+=" -d \"$domains\""
    [[ -n "$check_hours" ]] && cron_cmd+=" -c $check_hours"
    [[ "$local_mode" == "true" ]] && cron_cmd+=" --local"
    cron_cmd+=" $CRON_TAG"

    if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        echo "Scheduled SSL check already exists. Use '$(basename "$0") cron del' first."
        crontab -l 2>/dev/null | grep "$CRON_TAG"
        exit 1
    fi

    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -

    log "Scheduled SSL check added:"
    log "  Schedule: $schedule"
    log "  Command:  $script_path check"
    log ""
    log "Current crontab:"
    crontab -l 2>/dev/null | grep "$CRON_TAG" || true
}

cron_del() {
    if ! crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        echo "No scheduled SSL check found."
        exit 0
    fi

    load_config

    log "Removing scheduled SSL check:"
    crontab -l 2>/dev/null | grep "$CRON_TAG"

    crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab -

    log ""
    log "Scheduled SSL check removed successfully."
}

cron_list() {
    if ! crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        echo "No scheduled SSL check found."
        exit 0
    fi

    echo "Scheduled SSL check tasks:"
    crontab -l 2>/dev/null | grep "$CRON_TAG"
}

do_cron() {
    local action="${1:-}"
    shift || true

    case "$action" in
        add)
            cron_add "$@"
            ;;
        del|delete|remove)
            cron_del "$@"
            ;;
        list|ls)
            cron_list
            ;;
        *)
            show_cron_help
            exit 1
            ;;
    esac
}

show_help() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

SSL certificate monitoring tool for WebDAV.

Commands:
    check           Check SSL certificates (default)
    init            Initialize .env configuration and setup cron
    cron add        Add scheduled check task
    cron del        Remove scheduled check task
    cron list       List scheduled check tasks
    help            Show this help message

Examples:
    # Initialize configuration and setup cron
    $(basename "$0") init

    # Check SSL certificates
    $(basename "$0") check

    # Add daily check at 2am
    $(basename "$0") cron add "0 2 * * *"

    # Add random daily check (0-8am)
    $(basename "$0") cron add random

    # List scheduled tasks
    $(basename "$0") cron list

    # Remove all scheduled tasks
    $(basename "$0") cron del

Configuration:
    Create .env file in script directory or run '$(basename "$0") init'.
    See '$(basename "$0") check --help' for available options.

EOF
}

show_check_help() {
    cat << EOF
Usage: $(basename "$0") check [options]

Check SSL certificates on WebDAV for updates.

Options:
    -d, --domains DOMAINS    Domain list (comma-separated, override .env)
    -c, --check-hours HOURS  Check time range in hours (default: from .env)
    -o, --output DIR         Certificate save directory (default: from .env)
    -l, --local              Check local certificates only (skip WebDAV)
    -?, --help               Show this help message

Configuration (.env):
    WebDAV:
        WEBDAV_USER=username
        WEBDAV_PASS=password
        WEBDAV_URL_TEMPLATE=https://dav.com/%s.fullchain.cer

    Domains:
        DOMAINS=example.com,example.cn
        CHECK_HOURS=48

    Storage:
        CERTS_SAVE_DIR=certs
        LOG_FILE=ssl-check.log
        LOCAL_MODE=false

Examples:
    # Check all configured domains
    $(basename "$0") check

    # Check specific domains
    $(basename "$0") check -d "example.com,example.cn"

    # Check with custom time range
    $(basename "$0") check -c 24

    # Check local certificates only
    $(basename "$0") check --local

EOF
}

show_cron_help() {
    cat << EOF
Usage: $(basename "$0") cron <action> [options]

Manage scheduled SSL check tasks.

Actions:
    add <schedule>          Add a scheduled check
    del [-t <type>]         Remove scheduled check (all or by type)
    list                    List scheduled checks

Options:
    -d, --domains DOMAINS   Domain list (comma-separated)
    -c, --check-hours HOURS Check time range in hours
    --local                 Check local certificates only

Schedule Formats:
    Standard cron:  "0 2 * * *"           # Daily at 2am
    Random daily:   "random"              # Random time between 0-8am
    Every N hours:  "0 */6 * * *"         # Every 6 hours

Examples:
    $(basename "$0") cron add "0 2 * * *"                    # Daily at 2am
    $(basename "$0") cron add random                         # Random daily
    $(basename "$0") cron add "0 */6 * * *" -c 12            # Every 6 hours
    $(basename "$0") cron del                                # Remove all checks
    $(basename "$0") cron list

EOF
}

do_check() {
    local domains="" check_hours="" output_dir="" local_mode="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domains) domains="$2"; shift 2 ;;
            -c|--check-hours) check_hours="$2"; shift 2 ;;
            -o|--output) output_dir="$2"; shift 2 ;;
            -l|--local) local_mode="true"; shift ;;
            -?|--help) show_check_help; exit 0 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    load_config

    [[ -n "$domains" ]] && DOMAINS="$domains"
    [[ -n "$check_hours" ]] && CHECK_HOURS="$check_hours"
    [[ -n "$output_dir" ]] && CERTS_SAVE_DIR="$output_dir"
    [[ "$local_mode" == "true" ]] && LOCAL_MODE="true"

    setup_dirs

    if [[ -z "$DOMAINS" ]]; then
        echo "Error: DOMAINS not configured in .env" >&2
        exit 1
    fi

    local restart_needed=false
    IFS=',' read -r -a domain_array <<< "$DOMAINS"

    for domain in "${domain_array[@]}"; do
        domain=$(echo "$domain" | xargs)
        if [[ -n "$domain" ]]; then
            if check_domain_update "$domain"; then
                download_certs "$domain"
                run_upgrade_scripts "$domain"
                restart_needed=true
            fi
        fi
    done

    if [[ "$restart_needed" == "true" ]]; then
        echo "Certificate update detected, running restart scripts..."
        run_restart_scripts
    else
        echo "No certificate updates detected in the past $CHECK_HOURS hours."
    fi
}

main() {
    local command="${1:-check}"

    case "$command" in
        check)
            shift
            do_check "$@"
            ;;
        init)
            init_env
            setup_dirs
            echo ""
            echo "Next steps:"
            echo "  1. Edit $CONFIG_FILE with your WebDAV configuration"
            echo "  2. Run '$(basename "$0") cron add' to setup scheduled checks"
            ;;
        cron)
            shift
            do_cron "$@"
            ;;
        help|-?|--help)
            show_help
            ;;
        *)
            echo "Unknown command: $command" >&2
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
