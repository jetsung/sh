#!/usr/bin/env bash

#============================================================
# File: nginx-init.sh
# Description: Nginx 初始化解耦配置脚本
#   - 自动生成目录结构和配置片段，支持 ACME 自动化（letsencrypt, zerossl, google）。
#   - 包含默认 HTTP/HTTPS 站点及自签名哑证书生成逻辑，防止窜站。
#   - 支持自动补全 nginx.conf 的模块加载和配置导入逻辑（具有幂等性）。
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.4
# CreatedAt: 2026-03-16
# UpdatedAt: 2026-03-16
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

# --- 默认值及环境变量读取 ---
NGINX_ROOT=""
NGINX_CONF=""
ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@example.com"}
SELECTED_PROVIDER=""
INPUT_EAB_ID=""
INPUT_EAB_KEY=""

# 预设的 EAB 默认占位符
DEFAULT_EAB_ID="<EAB_ID>"
DEFAULT_EAB_KEY="<EAB_HMAC_KEY>"

ZEROSSL_EAB_ID=${ZEROSSL_EAB_ID:-"$DEFAULT_EAB_ID"}
ZEROSSL_EAB_HMAC_KEY=${ZEROSSL_EAB_HMAC_KEY:-"$DEFAULT_EAB_KEY"}
GOOGLE_EAB_ID=${GOOGLE_EAB_ID:-"$DEFAULT_EAB_ID"}
GOOGLE_EAB_HMAC_KEY=${GOOGLE_EAB_HMAC_KEY:-"$DEFAULT_EAB_KEY"}

# --- 参数解析 ---
USER_SET_EMAIL=false
USER_SET_EAB=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--root)
            NGINX_ROOT="$2"
            shift 2
            ;;
        -c|--config)
            NGINX_CONF="$2"
            shift 2
            ;;
        -e|--email)
            ADMIN_EMAIL="$2"
            USER_SET_EMAIL=true
            shift 2
            ;;
        -p|--provider)
            SELECTED_PROVIDER=$(echo "$2" | tr '[:upper:]' '[:lower:]')
            shift 2
            ;;
        --eab-id)
            INPUT_EAB_ID="$2"
            USER_SET_EAB=true
            shift 2
            ;;
        --eab-key)
            INPUT_EAB_KEY="$2"
            USER_SET_EAB=true
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -r, --root PATH         Nginx 配置根目录 (默认: 当前目录)"
            echo "  -c, --config PATH       nginx.conf 实际路径 (指定后将自动补全配置)"
            echo "  -e, --email EMAIL       管理邮箱 (默认: $ADMIN_EMAIL)"
            echo "  -p, --provider NAME     ACME 提供商 (zerossl, google, letsencrypt)"
            echo "      --eab-id ID         External Account Binding ID"
            echo "      --eab-key KEY       External Account Binding HMAC Key"
            echo "  -h, --help              显示此帮助信息"
            exit 0
            ;;
        *)
            if [[ -z "$NGINX_ROOT" ]] && [[ ! "$1" =~ ^- ]]; then
                NGINX_ROOT="$1"
                shift
            else
                echo "未知参数: $1"
                exit 1
            fi
            ;;
    esac
done

# --- 目录逻辑处理 ---
if [[ -n "$NGINX_CONF" ]]; then
    if [[ -z "$NGINX_ROOT" ]]; then
        NGINX_ROOT=$(dirname "$(realpath "$NGINX_CONF")")
    fi
elif [[ -n "$NGINX_ROOT" ]]; then
    potential_conf="$NGINX_ROOT/nginx.conf"
    if [[ -f "$potential_conf" ]]; then
        NGINX_CONF="$potential_conf"
    fi
else
    NGINX_ROOT="."
    if [[ -f "./nginx.conf" ]]; then
        NGINX_CONF="./nginx.conf"
    fi
fi

NGINX_ROOT=${NGINX_ROOT:-"."}
ACME_CONF_FILE="$NGINX_ROOT/extend/acme.conf"

# --- 尝试从现有配置中恢复信息 ---
if [[ -f "$ACME_CONF_FILE" ]]; then
    if [[ "$USER_SET_EMAIL" = false ]]; then
        EXISTING_EMAIL=$(grep -m 1 "contact mailto:" "$ACME_CONF_FILE" | awk -F'mailto:' '{print $2}' | tr -d ' ;' || true)
        if [[ -n "$EXISTING_EMAIL" ]]; then
            ADMIN_EMAIL="$EXISTING_EMAIL"
        fi
    fi
    if [[ "$SELECTED_PROVIDER" != "zerossl" || "$USER_SET_EAB" = false ]]; then
        Z_LINE=$(grep "acme_issuer zerossl" -A 10 "$ACME_CONF_FILE" | grep "external_account_key" || true)
        if [[ -n "$Z_LINE" ]]; then
            ZEROSSL_EAB_ID=$(echo "$Z_LINE" | awk '{print $2}')
            ZEROSSL_EAB_HMAC_KEY=$(echo "$Z_LINE" | awk -F'data:' '{print $2}' | tr -d ' ;')
        fi
    fi
    if [[ "$SELECTED_PROVIDER" != "google" || "$USER_SET_EAB" = false ]]; then
        G_LINE=$(grep "acme_issuer google" -A 10 "$ACME_CONF_FILE" | grep "external_account_key" || true)
        if [[ -n "$G_LINE" ]]; then
            GOOGLE_EAB_ID=$(echo "$G_LINE" | awk '{print $2}')
            GOOGLE_EAB_HMAC_KEY=$(echo "$G_LINE" | awk -F'data:' '{print $2}' | tr -d ' ;')
        fi
    fi
fi

# --- 参数校验 ---
if [[ "$SELECTED_PROVIDER" == "zerossl" && "$USER_SET_EAB" = true ]]; then
    ZEROSSL_EAB_ID="$INPUT_EAB_ID"; ZEROSSL_EAB_HMAC_KEY="$INPUT_EAB_KEY"
elif [[ "$SELECTED_PROVIDER" == "google" && "$USER_SET_EAB" = true ]]; then
    GOOGLE_EAB_ID="$INPUT_EAB_ID"; GOOGLE_EAB_HMAC_KEY="$INPUT_EAB_KEY"
fi

echo "正在初始化 Nginx 配置结构于: $NGINX_ROOT ..."

# 创建目录结构
mkdir -p "$NGINX_ROOT"/{extend,wildcard,conf.d,acme/{letsencrypt,zerossl,google},modules,ssl}
mkdir -p /data/wwwlogs /data/wwwroot/default

# --- 生成自签名哑证书 (Dummy SSL) ---
DUMMY_CRT="$NGINX_ROOT/ssl/dummy.crt"
DUMMY_KEY="$NGINX_ROOT/ssl/dummy.key"
if [[ ! -f "$DUMMY_CRT" || ! -f "$DUMMY_KEY" ]]; then
    if command -v openssl >/dev/null 2>&1; then
        echo "正在生成自签名哑证书..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$DUMMY_KEY" -out "$DUMMY_CRT" \
            -subj "/C=CN/ST=Default/L=Default/O=Default/CN=dummy" 2>/dev/null
    fi
fi

# 1. extend/acme.conf
if [[ -n "$SELECTED_PROVIDER" || "$USER_SET_EMAIL" = true || ! -f "$ACME_CONF_FILE" ]]; then
    cat <<EOF > "$ACME_CONF_FILE"
resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
resolver_timeout 5s;
acme_shared_zone zone=ngx_acme_shared:1M;

acme_issuer letsencrypt {
    uri https://acme-v02.api.letsencrypt.org/directory;
    state_path /etc/nginx/acme/letsencrypt;
    accept_terms_of_service;
    contact mailto:$ADMIN_EMAIL;
}

acme_issuer zerossl {
    uri https://acme.zerossl.com/v2/DV90;
    state_path /etc/nginx/acme/zerossl;
    accept_terms_of_service;
    contact mailto:$ADMIN_EMAIL;
    external_account_key $ZEROSSL_EAB_ID data:$ZEROSSL_EAB_HMAC_KEY;
}

acme_issuer google {
    uri https://dv.acme-v02.api.pki.goog/directory;
    state_path /etc/nginx/acme/google;
    accept_terms_of_service;
    contact mailto:$ADMIN_EMAIL;
    external_account_key $GOOGLE_EAB_ID data:$GOOGLE_EAB_HMAC_KEY;
}
EOF
fi

# 2. wildcard/acme.conf, 3. ssl.conf, 4. http_to_https.conf, 5. maps.conf, 6. robots_disallow.conf, 7. upstreams.conf
# (篇幅原因，逻辑与之前一致，仅添加 [ ! -f ] 保护)
[ ! -f "$NGINX_ROOT/wildcard/acme.conf" ] && cat <<'EOF' > "$NGINX_ROOT/wildcard/acme.conf"
include extend/ssl.conf;
ssl_certificate     $acme_certificate;
ssl_certificate_key $acme_certificate_key;
ssl_certificate_cache max=10;
EOF

[ ! -f "$NGINX_ROOT/extend/ssl.conf" ] && cat <<'EOF' > "$NGINX_ROOT/extend/ssl.conf"
listen 443 ssl;
listen 443 quic;
listen [::]:443 ssl;
listen [::]:443 quic;
http2 on;
http3 on;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers DEFAULT;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_buffer_size 1400;
add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload";
add_header Alt-Svc 'h3=":443"; ma=86400';
ssl_stapling off;
ssl_stapling_verify off;
error_page 403 https://$host$request_uri;
EOF

[ ! -f "$NGINX_ROOT/extend/http_to_https.conf" ] && cat <<'EOF' > "$NGINX_ROOT/extend/http_to_https.conf"
if ($skip_https_redirect = 1) {
    return 301 https://$host$request_uri;
}
EOF

[ ! -f "$NGINX_ROOT/extend/maps.conf" ] && cat <<'EOF' > "$NGINX_ROOT/extend/maps.conf"
map $http_user_agent $bad_bot {
    default 0;
    "~*ClaudeBot" 1;
}
map $host $skip_https_redirect {
    default 1;
}
EOF

[ ! -f "$NGINX_ROOT/extend/robots_disallow.conf" ] && cat <<'EOF' > "$NGINX_ROOT/extend/robots_disallow.conf"
location = /robots.txt {
    add_header Content-Type text/plain;
    return 200 "User-agent: *\nDisallow: /\n";
}
EOF

[ ! -f "$NGINX_ROOT/extend/upstreams.conf" ] && cat <<EOF > "$NGINX_ROOT/extend/upstreams.conf"
upstream server1 {
    server 127.0.0.1:9120;
}
EOF

# 8. conf.d/http_80.conf
[ ! -f "$NGINX_ROOT/conf.d/http_80.conf" ] && cat <<'EOF' > "$NGINX_ROOT/conf.d/http_80.conf"
server {
    listen       80 default_server;
    server_name  localhost _;

    access_log  /data/wwwlogs/access.log;

    location / {
        root /data/wwwroot/default;
        index  index.html index.htm;
    }

    include extend/robots_disallow.conf;
}
EOF

# 9. conf.d/https_443.conf
[ ! -f "$NGINX_ROOT/conf.d/https_443.conf" ] && cat <<'EOF' > "$NGINX_ROOT/conf.d/https_443.conf"
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    http2 on;

    listen 443 quic default_server;
    listen [::]:443 quic default_server;
    http3 on;

    add_header Alt-Svc 'h3=":443"; ma=86400';

    ssl_protocols TLSv1.3 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!MD5;

    server_name _;

    ssl_certificate ssl/dummy.crt;
    ssl_certificate_key ssl/dummy.key;

    return 444;
}
EOF

# --- 幂等性补全 nginx.conf 配置 ---
if [[ -n "$NGINX_CONF" && -f "$NGINX_CONF" ]]; then
    echo "正在检查并幂等更新配置文件: $NGINX_CONF ..."
    
    # 1. 补全 load_module
    MODULE_FILE="$NGINX_ROOT/modules/ngx_http_acme_module.so"
    if [[ -f "$MODULE_FILE" ]]; then
        # 严格检查，忽略空格并处理转义
        if ! grep -qE "load_module.*ngx_http_acme_module\.so" "$NGINX_CONF"; then
            echo "添加模块加载..."
            sed -i "1i load_module modules/ngx_http_acme_module.so;" "$NGINX_CONF"
        fi
    fi

    # 2. 补全 http 块内的 include
    declare -A INCLUDES=(
        ["extend/maps.conf"]="include extend/maps.conf;"
        ["extend/acme.conf"]="include extend/acme.conf;"
        ["extend/upstreams.conf"]="include extend/upstreams.conf;"
        ["conf.d/\*.conf"]="include conf.d/*.conf;"
    )

    for key in "${!INCLUDES[@]}"; do
        val="${INCLUDES[$key]}"
        # 使用正则表达式匹配，处理 * 和可能的路径前缀
        if ! grep -qE "include[[:space:]]+([^[:space:]]*/)?${key};" "$NGINX_CONF"; then
            echo "正在添加指令: $val"
            if grep -q "http {" "$NGINX_CONF"; then
                sed -i "/http {/a \    $val" "$NGINX_CONF"
            else
                echo "$val" >> "$NGINX_CONF"
            fi
        fi
    done
fi

echo "------------------------------------------------"
echo "初始化完成！"
echo "提示：已修复 include 检查逻辑，确保不会重复注入指令。"
echo "------------------------------------------------"
