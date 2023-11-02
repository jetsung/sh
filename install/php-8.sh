#!/bin/bash

## libiconv
#wget https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.16.tar.gz
#tar xzf libiconv-1.16.tar.gz
#./configure --prefix=/usr/local/libiconv
#make -j4 && make install
#rm -rf libiconv-1.16
#ln -s /usr/local/libiconv/lib/libiconv.so.2 /usr/lib64/libiconv.so.2

#make clean
#--with-zip=/usr/local \
#--with-openssl=/usr/local/openssl \

main() {
	./buildconf

	./configure --prefix=/usr/local/php \
			--with-config-file-path=/usr/local/php/etc \
			--with-config-file-scan-dir=/usr/local/php/etc/php.d \
			--with-fpm-user=www \
			--with-fpm-group=www \
			--with-mysqli=mysqlnd \
			--with-pdo-mysql=mysqlnd \
			--with-iconv=/usr/local/libiconv \
			--with-curl=/usr/local/curl \
			--with-sodium=/usr/local \
			--with-freetype \
			--with-jpeg \
			--with-zlib \
			--with-password-argon2 \
			--with-mhash \
			--with-xsl \
			--with-gettext \
			--disable-debug \
			--disable-rpath \
			--enable-fpm \
			--enable-opcache \
			--enable-fileinfo \
			--enable-mysqlnd \
			--enable-xml \
			--enable-bcmath \
			--enable-shmop \
			--enable-exif \
			--enable-sysvsem \
			--enable-mbregex \
			--enable-mbstring \
			--enable-gd \
			--enable-pcntl \
			--enable-sockets \
			--enable-ftp \
			--enable-intl \
			--enable-soap


	make -j4

	make install
}

#:<<BLOCK
#BLOCK

#openssl
#cd ext/openssl
#mv config0.m4 config.m4
#phpize
#./configure --with-openssl --with-php-config=/usr/local/php/bin/php-config
#make
#make install
#echo "extension=openssl.so" > /usr/local/php/etc/php.d/00-zip.ini

main "$@" || exit 1
