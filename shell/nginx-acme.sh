#!/usr/bin/env bash

#============================================================
# File: nginx-acme.sh
# Description: 编译 nginx-acme 模块并集成到当前系统 Nginx
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-03-15
# UpdatedAt: 2026-03-15
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

USER_ID="$(id -u)"

sudo_exec() {
    if [[ "$USER_ID" -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

check_is_command() {
    command -v "$1" >/dev/null 2>&1
}

# 1. 获取最新 nginx-acme 版本和下载链接
echo "正在获取 nginx-acme 最新版本信息..."
ACME_RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/nginx/nginx-acme/releases/latest)
ACME_VERSION=$(echo "$ACME_RELEASE_INFO" | jq -r '.tag_name')
ACME_DOWNLOAD_URL=$(echo "$ACME_RELEASE_INFO" | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url')

echo "最新版本: $ACME_VERSION"

# 2. 获取当前系统 Nginx 版本
if ! check_is_command "nginx"; then
    echo "错误: 系统未安装 nginx，无法编译模块。"
    exit 1
fi

NGINX_VER=$(nginx -v 2>&1 | cut -d '/' -f 2)
echo "当前 Nginx 版本: $NGINX_VER"

# 3. 准备工作目录
WORK_DIR=$(mktemp -d /tmp/nginx-acme-build.XXXXXX)
cd "$WORK_DIR"

# 4. 下载源码
echo "正在下载 nginx-acme 源码..."
curl -fsSL "$ACME_DOWNLOAD_URL" -o "nginx-acme.tar.gz"
tar -xzf "nginx-acme.tar.gz"
ACME_SRC_DIR=$(find . -maxdepth 1 -type d -name "nginx-acme-*" | head -n 1)

echo "正在下载 Nginx $NGINX_VER 源码..."
curl -fsSL "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz" -o "nginx.tar.gz"
tar -xzf "nginx.tar.gz"
NGINX_SRC_DIR="nginx-${NGINX_VER}"

# 5. 安装编译依赖
echo "正在安装编译依赖..."
sudo_exec apt-get update -y
sudo_exec apt-get install -y clang pkg-config libssl-dev libpcre2-dev zlib1g-dev libclang-dev

# 6. 编译模块
echo "开始编译模块..."
cd "$NGINX_SRC_DIR"

# 获取原始编译参数并添加动态模块支持
# 注意：必须包含 --with-compat 以确保二进制兼容
./configure --with-compat --with-http_ssl_module --add-dynamic-module="../$ACME_SRC_DIR"

make modules

# 7. 安装模块
MODULE_PATH=$(nginx -V 2>&1 | grep -oP "modules-path=\K[^ ]*")
if [[ -z "$MODULE_PATH" ]]; then
    MODULE_PATH="/usr/lib/nginx/modules"
fi

echo "编译完成。正在将模块复制到 $MODULE_PATH..."
sudo_exec mkdir -p "$MODULE_PATH"
sudo_exec cp objs/ngx_http_acme_module.so "$MODULE_PATH/"

# 8. 测试模块是否正常加载
echo "正在验证模块是否加载正常..."
TEST_CONF=$(mktemp /tmp/nginx-acme-test.XXXXXX.conf)
cat > "$TEST_CONF" <<EOF
error_log /tmp/nginx-acme-test-error.log;
pid /tmp/nginx-acme-test.pid;
load_module $MODULE_PATH/ngx_http_acme_module.so;
events {
    worker_connections 1024;
}
http {
    access_log /tmp/nginx-acme-test-access.log;
}
EOF

if sudo_exec nginx -t -c "$TEST_CONF" > /dev/null 2>&1; then
    echo "验证成功: 模块 $MODULE_PATH/ngx_http_acme_module.so 已成功加载并与当前 Nginx 兼容。"
else
    echo "验证失败: 模块加载出错。请检查错误日志: /tmp/nginx-acme-test-error.log"
    sudo_exec cat /tmp/nginx-acme-test-error.log
    rm -f "$TEST_CONF"
    exit 1
fi

rm -f "$TEST_CONF" /tmp/nginx-acme-test-error.log /tmp/nginx-acme-test.pid /tmp/nginx-acme-test-access.log

echo "----------------------------------------------------"
echo "nginx-acme 模块已安装并验证成功！"
echo "模块位置: $MODULE_PATH/ngx_http_acme_module.so"
echo "请在您的主 nginx.conf 顶层添加以下行以启用模块:"
echo "load_module modules/ngx_http_acme_module.so;"
echo "----------------------------------------------------"

# 清理
rm -rf "$WORK_DIR"
