#/bin/bash

run_group=www
run_user=www
nginx_install_dir=/usr/local/nginx
nginx_conf_dir=conf

do_install() {
    id -g ${run_group} >/dev/null 2>&1
    [ $? -ne 0 ] && groupadd ${run_group}
    id -u ${run_user} >/dev/null 2>&1
    [ $? -ne 0 ] && useradd -g ${run_group} -M -s /sbin/nologin ${run_user}

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
        #--with-openssl=/usr/local/openssl \
        #--with-pcre \
        --with-pcre-jit \
        --with-ld-opt='-ljemalloc'

    make -j 4
    
    make install
}

print_message() {
    if [ -e "${nginx_install_dir}/conf/nginx.conf" ]; then
        echo "Nginx installed successfully! "
    else
        echo "Nginx install failed, Please Contact the author! "
        kill -9 $$
    fi
}

set_env() {
    [ -z "`grep ^'export PATH=' /etc/profile`" ] && echo "export PATH=${nginx_install_dir}/sbin:\$PATH" >> /etc/profile
    [ -n "`grep ^'export PATH=' /etc/profile`" -a -z "`grep ${nginx_install_dir} /etc/profile`" ] && sed -i "s@^export PATH=\(.*\)@export PATH=${nginx_install_dir}/sbin:\1@" /etc/profile
    . /etc/profile

    mv ${nginx_install_dir}/conf/nginx.conf{,_bk}
    cp ${nginx_conf_dir}/nginx.conf ${nginx_install_dir}/conf/nginx.conf

    [ -z "`grep '/php-fpm_status' ${nginx_install_dir}/conf/nginx.conf`" ] &&  sed -i "s@index index.html index.php;@index index.html index.php;\n    location ~ /php-fpm_status {\n        #fastcgi_pass remote_php_ip:9000;\n        fastcgi_pass unix:/dev/shm/php-cgi.sock;\n        fastcgi_index index.php;\n        include fastcgi.conf;\n        allow 127.0.0.1;\n        deny all;\n        }@" ${nginx_install_dir}/conf/nginx.conf
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

    sed -i "s@^user www www@user ${run_user} ${run_user}@" ${nginx_install_dir}/conf/nginx.conf
}

do_install

print_message

set_env
