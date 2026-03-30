#!/usr/bin/env bash

#============================================================
# File: php.sh
# Description: 编译 PHP 环境
# URL: https://fx4.cn/php
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-03-27
# UpdatedAt: 2026-03-27
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

check_is_command() {
    command -v "$1" >/dev/null 2>&1
}

check_in_china() {
    if [[ -n "${CN:-}" ]]; then
        return 0 # 手动指定
    fi
    if [[ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" == "000" ]]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
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

do_remove_https() {
    local url="$1"
    if [[ -n "$NO_HTTPS" ]]; then
        # shellcheck disable=SC2001
        echo "$url" | sed 's|https:/||2'

    else 
        echo "$url"
    fi
}

########################## 以上为通用函数 #########################

china_mirror() {
    if [[ -z "$IS_CHINA" ]]; then
        return 0
    fi

    case "${1:-}" in
        deb)
            # Debian
            if [[ -f "/etc/apt/sources.list.d/debian.sources" ]]; then
                sed -i.bak 's#deb.debian.org#mirrors.aliyun.com#g' /etc/apt/sources.list.d/debian.sources
            fi

            # Ubuntu
            if [[ -f "/etc/apt/sources.list.d/ubuntu.sources" ]]; then
                sed -i.bak 's#//.*archive.ubuntu.com#//mirrors.ustc.edu.cn#g' /etc/apt/sources.list.d/ubuntu.sources
                sed -i.bak 's#security.ubuntu.com#mirrors.aliyun.com#g' /etc/apt/sources.list.d/ubuntu.sources
            fi

            # Debian / Ubuntu
            if [[ -f "/etc/apt/sources.list" ]]; then
                sed -i.bak 's#deb.debian.org#mirrors.aliyun.com#g' /etc/apt/sources.list

                sed -i.bak 's#//.*archive.ubuntu.com#//mirrors.ustc.edu.cn#g' /etc/apt/sources.list
                sed -i.bak 's#security.ubuntu.com#mirrors.aliyun.com#g' /etc/apt/sources.list
            fi
            ;;

        dnf|yum)
            # AlmaLinux
              sed -e 's|^mirrorlist=|#mirrorlist=|g' \
                -e 's|^# baseurl=https://repo.almalinux.org|baseurl=https://mirrors.aliyun.com|g' \
                -i.bak \
                /etc/yum.repos.d/almalinux*.repo
            ;;
        apk)
            sed -i.bak 's#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories
            ;;
        *)
            echo "未检测到已知包管理器，请手动安装依赖：curl xz build-essential"
            return 1
    esac
}

# 支持多个 Linux 平台的依赖安装
install_deps() {
    if check_is_command "apt-get"; then
        china_mirror deb
        echo "检测到 Debian/Ubuntu 系统，安装依赖..."
        apt-get update
        apt-get install -y \
            build-essential \
            curl \
            xz-utils \
            pkg-config \
            autoconf \
            libxml2-dev \
            libssl-dev \
            libsqlite3-dev \
            zlib1g-dev \
            libcurl4-openssl-dev \
            libpng-dev \
            libonig-dev \
            libzip-dev \
            libjpeg62-turbo-dev \
            libpq-dev \
            libsodium-dev \
            libfreetype-dev \
            libicu-dev \
            libxslt1-dev \
            libargon2-dev \
            libtidy-dev \
            libbz2-dev \
            procps
    elif check_is_command "dnf"; then
        china_mirror dnf
        echo "检测到 RHEL 系列系统，安装依赖..."
        # dnf makecache
        dnf update -y
        dnf install -y epel-release
        dnf groupinstall -y "Development Tools"
        dnf install -y \
            curl \
            libxml2-devel \
            openssl-devel \
            sqlite-devel \
            bzip2-devel \
            libcurl-devel \
            libpng-devel \
            libjpeg-turbo-devel \
            freetype-devel \
            oniguruma-devel \
            postgresql-devel \
            libsodium-devel \
            libargon2-devel \
            libtidy-devel \
            libxslt-devel \
            libzip-devel
    elif check_is_command "yum"; then
        china_mirror yum
        echo "检测到 RHEL 系列系统，安装依赖..."
        yum install -y curl
    elif check_is_command "apk"; then
        china_mirror apk
        echo "检测到 Alpine 系统，安装依赖..."
        apk update
        apk add build-base linux-headers autoconf shadow
        apk add \
            curl \
            pkgconfig \
            libxml2-dev \
            openssl-dev \
            sqlite-dev \
            bzip2-dev \
            curl-dev \
            libpng-dev \
            libjpeg-turbo-dev \
            freetype-dev \
            gettext-dev \
            icu-dev \
            oniguruma-dev \
            postgresql-dev \
            libsodium-dev \
            argon2-dev \
            tidyhtml-dev \
            libxslt-dev \
            libzip-dev
    elif check_is_command "pacman"; then
        echo "检测到 Arch Linux 系统，安装依赖..."
        pacman -Syu --noconfirm --needed curl
    else
        echo "未检测到已知包管理器，请手动安装依赖：curl xz build-essential"
        return 1
    fi
}

get_download_url() {
    echo "https://www.php.net/distributions/php-${1:-8.5.4}.tar.xz"
}

download_and_build() {
    install_deps

    download_exact

    optimized

    setting_phpfpm
}

download_exact() {
    local download_file="php.tar.xz"
    local local_file="php-${PHP_VERSION}.tar.xz"
    TMP_DIR=$(mktemp -d /tmp/php.XXXXXX)
    if [[ -f "$local_file" ]]; then
        cp "$local_file" "${TMP_DIR}/${download_file}"
    fi

    # shellcheck disable=SC2329
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null
    if [[ ! -f "$download_file" ]]; then
        _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
        if ! curl -fsSL "$_download_url" -o "$download_file"; then
            echo "Error: Failed to download $download_file"
            exit 1
        fi
    fi

    if ! tar -xJf "$download_file" --strip-components=1; then 
        echo "Error: Extraction failed"
        rm -f "$download_file"
        exit 1
    fi

    build
    
    setting

    popd >/dev/null
}

build() {
    # shellcheck disable=SC2086
    ./configure --prefix=/usr/local/php \
        --with-config-file-path=/usr/local/php/etc \
        --with-config-file-scan-dir=/usr/local/php/etc/conf.d \
        --enable-fpm \
        --with-fpm-user=${FPM_USER} \
        --with-fpm-group=${FPM_USER} \
        --with-mysqli \
        --with-pdo-mysql \
        --with-pgsql \
        --with-pdo-pgsql \
        --with-openssl \
        --with-zlib \
        --with-curl \
        --with-zip \
        --with-bz2 \
        --with-iconv \
        --with-pear \
        --with-jpeg \
        --with-sodium \
        --with-password-argon2 \
        --with-mhash \
        --with-gettext \
        --with-freetype \
        --with-xsl \
        --with-tidy \
        --with-imap \
        --with-pear \
        --disable-debug \
        --disable-rpath \
        --enable-huge-code-pages \
        --enable-mysqlnd \
        --enable-opcache \
        --enable-gd \
        --enable-mbstring \
        --enable-soap \
        --enable-fileinfo \
        --enable-xml \
        --enable-bcmath \
        --enable-calendar \
        --enable-exif \
        --enable-ftp \
        --enable-sockets \
        --enable-sysvsem \
        --enable-sysvshm \
        --enable-sysvmsg \
        --enable-ipv6 \
        --enable-shmop \
        --enable-mbregex \
        --enable-pcntl \
        --enable-intl \
        ${CONFIGURE_ARGS:-}

    # make -j6
    make "-j$(nproc)"
    make install
}

setting() {
    # 1. 创建配置文件目录
    mkdir -p /usr/local/php/etc/conf.d

    # 2. 拷贝生产环境配置文件
    cp php.ini-production /usr/local/php/etc/php.ini

    # 3. 准备 FPM 配置文件
    cp /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf
    cp /usr/local/php/etc/php-fpm.d/www.conf.default /usr/local/php/etc/php-fpm.d/www.conf

    setting_env

    setting_ext_opcache

    install_ext_redis

    install_custom_extensions

    ldconfig
}

setting_env() {
    # shellcheck disable=SC2016
    LINE='export PATH=/usr/local/php/bin:/usr/local/php/sbin:$PATH'

    # 使用 grep 检查文件内容，如果返回非 0（即没找到），则执行写入
    grep -qF "$LINE" /etc/profile || echo "$LINE" >> /etc/profile

    set +u
    # shellcheck disable=SC1091
    source /etc/profile
    set -u
}

setting_ext_opcache() {
    cat > /usr/local/php/etc/conf.d/opcache.ini <<'EOF'
[opcache]
; 必须开启
opcache.enable=1
opcache.enable_cli=1          ; CLI 也建议开启（composer、artisan 等会受益）

; 推荐生产常用配置（根据服务器内存调整）
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.max_wasted_percentage=10
opcache.validate_timestamps=0   ; 生产环境建议关闭（部署后手动重启清缓存）
opcache.revalidate_freq=0
opcache.jit=tracing             ; PHP 8.5 JIT 默认推荐 tracing 或 function
opcache.jit_buffer_size=128M
EOF
}

# 函数：检查扩展是否已加载
check_loaded() {
    php -m | grep -q "^$1$"
    return $?
}

install_pecl_extension() {
    local ext="$1"
    if check_loaded "$ext"; then
        echo "✅ $ext already exists, skipping."
        return 0
    fi

    echo "⚙️  Installing $ext..."
    if yes "" | /usr/local/php/bin/pecl install "$ext"; then
        echo "extension=$ext.so" > "/usr/local/php/etc/conf.d/$ext.ini"
        echo "✅ $ext installed successfully."
    else
        echo "❌ $ext installation failed."
        return 1
    fi
}

install_custom_extensions() {
    if [[ -z "${EXTENSIONS:-}" ]]; then
        return 0
    fi

    echo "⚙️  Installing custom extensions: $EXTENSIONS"
    for ext in $EXTENSIONS; do
        install_pecl_extension "$ext"
    done
}

# 安装 igbinary
install_ext_igbinary() {
    if check_loaded igbinary; then
        echo "✅ igbinary already exists, skipping."
        return 0
    fi

    echo "⚙️  Installing igbinary..."
    /usr/local/php/bin/pecl install igbinary
    echo "extension=igbinary.so" > /usr/local/php/etc/conf.d/igbinary.ini
    echo "✅ igbinary installed successfully."    
}

install_ext_redis() {
    # 1. 先确保 igbinary 已安装
    install_ext_igbinary

    # 2. 检查 redis 是否已存在
    if check_loaded redis; then
        echo "✅ redis already exists, skipping."
        return 0
    fi 

    # 3. 不存在才执行安装
    echo "⚙️  Installing redis..."
    yes "" | /usr/local/php/bin/pecl install redis --configureoptions '--enable-redis-igbinary=yes --enable-redis-msgpack=no --enable-redis-lzf=no --enable-redis-zstd=no --enable-redis-lz4=no'
    echo "extension=redis.so" > /usr/local/php/etc/conf.d/redis.ini
    echo "✅ redis installed successfully."
}

optimized() {
    # 优化 php.ini
    # 1. 获取服务器总内存 (GB)
    MEM_GB=$(free -g | awk '/^Mem:/{print $2}')

    # 2. 根据内存大小动态设置 memory_limit
    # 如果内存 > 4G 设为 512M，否则设为 256M
    if [[ "$MEM_GB" -gt 4 ]]; then NEW_MEM="512M"; else NEW_MEM="256M"; fi

    # 3. 执行批量替换优化
    CONF_PATH="/usr/local/php/etc/php.ini"
    sed -i "s/memory_limit = .*/memory_limit = $NEW_MEM/" $CONF_PATH
    sed -i "s/upload_max_filesize = .*/upload_max_filesize = 50M/" $CONF_PATH
    sed -i "s/post_max_size = .*/post_max_size = 50M/" $CONF_PATH
    sed -i "s/max_execution_time = .*/max_execution_time = 300/" $CONF_PATH
    sed -i "s/;date.timezone =.*/date.timezone = Asia\/Shanghai/" $CONF_PATH

    echo "PHP.ini optimized, memory_limit: $NEW_MEM"

    # 优化 php-fpm
    # 获取 CPU 核心数
    CPU_CORES=$(nproc)

    # 计算子进程数 (原则：核心数 * 4 为起始点)
    MAX_CHILDREN=$((CPU_CORES * 4))
    START_SERVERS=$((CPU_CORES * 2))

    CONF_PATH="/usr/local/php/etc/php-fpm.d/www.conf"

    sed -i "s/pm.max_children = .*/pm.max_children = $MAX_CHILDREN/" $CONF_PATH
    sed -i "s/pm.start_servers = .*/pm.start_servers = $START_SERVERS/" $CONF_PATH
    sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = $CPU_CORES/" $CONF_PATH
    sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = $MAX_CHILDREN/" $CONF_PATH
    # 开启请求清理，防止内存泄漏
    sed -i "s/;pm.max_requests = .*/pm.max_requests = 1000/" $CONF_PATH

    echo "PHP-FPM optimized, max_children: $MAX_CHILDREN"    
}

setting_phpfpm() {
    mkdir -p /usr/local/php/var/run
    mkdir -p /usr/local/php/var/log

    # Create FPM user if not exists
    if ! id "$FPM_USER" >/dev/null 2>&1; then
        useradd -r -s /sbin/nologin "$FPM_USER"
    fi

    # Update www.conf user and group
    sed -i "s/^user = .*/user = $FPM_USER/" /usr/local/php/etc/php-fpm.d/www.conf
    sed -i "s/^group = .*/group = $FPM_USER/" /usr/local/php/etc/php-fpm.d/www.conf

    sed -i 's|^;pid = .*|pid = /usr/local/php/var/run/php-fpm.pid|' /usr/local/php/etc/php-fpm.conf

    if [[ -f /.dockerenv ]]; then
        echo "Notice: Running inside a Docker container.. To start PHP-FPM manually:"
        echo "  /usr/local/php/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php/etc/php-fpm.conf"
        return 0
    fi

    echo "Running on a Host/VM."

    cat <<EOF | tee /etc/systemd/system/php-fpm.service
[Unit]
Description=The PHP FastCGI Process Manager (8.5)
After=network.target

[Service]
Type=simple
PIDFile=/usr/local/php/var/run/php-fpm.pid
ExecStart=/usr/local/php/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 \$MAINPID
ExecStop=/bin/kill -SIGINT \$MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable php-fpm
    systemctl start php-fpm
    systemctl status php-fpm
}

main() {
    PHP_VERSION=8.5.4
    FPM_USER="www"
    EXTENSIONS=""
    CONFIGURE_ARGS=""
    IS_CHINA=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)   PHP_VERSION="$2"; shift 2 ;;
            -u|--user)      FPM_USER="$2"; shift 2 ;;
            -e|--extensions) EXTENSIONS="$2"; shift 2 ;;
            -c|--configure) CONFIGURE_ARGS="$2"; shift 2 ;;
            -h|--help)
                cat <<EOF
Usage: $0 [OPTIONS]

This script must be run as root.
Supports Debian (13), Alpine (3), AlmaLinux (10) etc.

Options:
  -v, --version VERSION      PHP version (default: 8.5.4)
  -u, --user USER            PHP-FPM user and group (default: www)
  -e, --extensions EXTS      Additional PECL extensions to install
  -c, --configure ARGS       Extra configure arguments
  -h, --help                 Show this help message
EOF
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [[ "$USER_ID" -ne 0 ]]; then
        echo "Error: This script must be run as root."
        exit 1
    fi

    if ! check_in_china; then
        CDN_URL=""
        IS_CHINA=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    DOWNLOAD_URL=$(get_download_url "$PHP_VERSION")

    if [[ -z "$DOWNLOAD_URL" ]]; then
        echo "Error: Failed to get download url"
        exit 1
    fi

    download_and_build

    echo ""

    if ! check_is_command "php"; then
        echo "php has not been installed successfully."
        echo ""
        exit 1
    fi

    echo ""
    echo "php has been installed successfully!"
    echo ""
    php --help
    echo ""
    php --version
    echo ""    
}

main "$@"