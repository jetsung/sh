#!/usr/bin/env bash

#============================================================
# File: nginx.sh
# Description: 安装 Nginx
# URL: 
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-
# UpdatedAt: 2025-
#============================================================


run_group=www
run_user=www
nginx_install_dir=/usr/local/nginx

# web directory, you can customize
wwwroot_dir=/data/wwwroot

# nginx Generate a log storage directory, you can freely specify.
wwwlogs_dir=/data/wwwlogs

install_dir=$(pwd)

get_stable_version() {
    #NGINX_VER="1.26.2"
    NGINX_VER=$(curl https://nginx.org/en/download.html | grep -oP '<table[^>]*>\K.*?(?=</table>)' | head -n 2 | grep -oP '(?<=nginx-)\d+\.\d+\.\d+' | tail -n 1)
}

download() {
    TMP_PATH=$(mktemp -d /tmp/nginx.XXX)
    cd "$TMP_PATH" || exit

    curl -fsSL -O "https://nginx.org/download/nginx-$NGINX_VER.tar.gz"
    tar -zxf "nginx-${NGINX_VER}".tar.gz
    cd "nginx-${NGINX_VER}" || exit
}

install() {
    id -g ${run_group} >/dev/null 2>&1
    if $? -ne 0; then
        groupadd ${run_group}
    fi

    id -u ${run_user} >/dev/null 2>&1
    if $? -ne 0; then
        useradd -g ${run_group} -M -s /sbin/nologin ${run_user}
    fi

    [ ! -d "${nginx_install_dir}" ] && mkdir -p ${nginx_install_dir}

    ./configure --prefix=${nginx_install_dir} \
        --user=${run_user} \
        --group=${run_group} \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_ssl_module \
        --with-http_gzip_static_module \
        --with-http_realip_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-pcre-jit \
        --with-ld-opt='-ljemalloc'

        #--with-openssl=/usr/local/openssl \
        #--with-pcre \

    make -j 4
    
    make install
}

setting() {
    cd "${install_dir}" || exit

    if ! grep -q '^export PATH=' /etc/profile; then
        echo "export PATH=${nginx_install_dir}/sbin:\$PATH" >> /etc/profile
    fi
    
    if grep -q '^export PATH=' /etc/profile && ! grep -q -E "${nginx_install_dir}" /etc/profile; then
        sed -i "s@^export PATH=\(.*\)@export PATH=${nginx_install_dir}/sbin:\1@" /etc/profile
    fi

    # shellcheck disable=SC1091
    . /etc/profile

    cp ../init.d/nginx.service /lib/systemd/system/
    sed -i "s@/usr/local/nginx@${nginx_install_dir}@g" /lib/systemd/system/nginx.service
    systemctl enable nginx    

    mv ${nginx_install_dir}/conf/nginx.conf{,_bk}
    cp ../conf/nginx.conf ${nginx_install_dir}/conf/nginx.conf

    if grep -q '/php-fpm_status' ${nginx_install_dir}/conf/nginx.conf; then
        sed -i "s@index index.html index.php;@index index.html index.php;\n    location ~ /php-fpm_status {\n        #fastcgi_pass remote_php_ip:9000;\n        fastcgi_pass unix:/dev/shm/php-cgi.sock;\n        fastcgi_index index.php;\n        include fastcgi.conf;\n        allow 127.0.0.1;\n        deny all;\n        }@" ${nginx_install_dir}/conf/nginx.conf
    fi

    cat > ${nginx_install_dir}/conf/proxy.conf << EOF
proxy_connect_timeout 300s;
proxy_send_timeout 900;
proxy_read_timeout 900;
proxy_buffer_size 32k;
proxy_buffers 4 64k;
proxy_busy_buffers_size 128k;
proxy_redirect off;
proxy_hide_header Vary;
proxy_set_header Accept-Encoding '';
proxy_set_header Referer \$http_referer;
proxy_set_header Cookie \$http_cookie;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
EOF

    sed -i "s@/data/wwwroot/default@${wwwroot_dir}/default@" ${nginx_install_dir}/conf/nginx.conf
    sed -i "s@/data/wwwlogs@${wwwlogs_dir}@g" ${nginx_install_dir}/conf/nginx.conf
    sed -i "s@^user www www@user ${run_user} ${run_group}@" ${nginx_install_dir}/conf/nginx.conf    

  # logrotate nginx log
  cat > /etc/logrotate.d/nginx << EOF
${wwwlogs_dir}/*nginx.log {
  daily
  rotate 5
  missingok
  dateext
  compress
  notifempty
  sharedscripts
  postrotate
    [ -e /var/run/nginx.pid ] && kill -USR1 \`cat /var/run/nginx.pid\`
  endscript
}
EOF

  ldconfig
  systemctl start nginx
}

print_message() {
    if [ -e "${nginx_install_dir}/conf/nginx.conf" ]; then
        echo "Nginx installed successfully! "
    else
        echo "Nginx install failed, Please Contact the author! "
        kill -9 $$
    fi
}

NGINX_VER="${1:-stable}"

if [ "${NGINX_VER}" = "stable" ]; then
    get_stable_version
fi

download

install

setting

print_message
