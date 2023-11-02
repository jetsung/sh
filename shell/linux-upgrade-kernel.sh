#!/usr/bin/env bash

###
#
# Upgrade Linux Kernel
# 当前仅测试 Deepin 23 通过
#
# Author: Jetsung Chan <jetsungchan@gmail.com>
#
###

##
# 最新代码位于：https://jihulab.com/-/snippets/2310
##

check_apt() {
	command -v apt >/dev/null 2>&1
}

install_deps() {
	apt -y install \
		libncurses5-dev \
		openssl \
		libssl-dev \
		build-essential \
		openssl \
		pkg-config \
		libc6-dev \
		bison \
		libidn11-dev \
		libidn11 \
		minizip \
		flex \
		libelf-dev #\
	# zlibc
}

pre_upgrade() {
	time make mrproper
	printf ":::::::make mrproper:::::::\n\n"

	CONFIG="/boot/config-$CURRENT_KERNEL"
	if [ ! -f "$CONFIG" ]; then
		CONFIG=$(find /boot/config* | awk '{print $1}')
	fi
	if [ ! -f "$CONFIG" ]; then
		printf "No configuration file found: %s\n" "$CONFIG"
		exit 1
	fi
	cp "$CONFIG" "./.config"

	# 经过多次验证。此命令需要在终端手动输入才可以选择按键选择。
	#
	# make menuconfig
	#
	# (4 次 Tab 键) -> Load(回车) -> OK(回车) -> (1 次 Tab 键) -> Exit(回车) -> Yes(回车)
	printf ":::::::::::::::::::::::::::::::::::::::::::::
Copy the following script and execute it: 
\e[1;33m%s\e[0m
\e[1;33m%s\e[0m
\e[1;33m%s\e[0m
\e[1;33m%s\e[0m
" "cd ./${EXTRACT}" "make menuconfig" "cd ../" "${0} ${1}"
}

do_upgrade() {
	pushd "./${EXTRACT}" >/dev/null 2>&1 || exit 1
	if [ ! -f "./.config" ]; then
		pre_upgrade "$@"
		exit
	fi

	CPU_COUNT=$(grep -c processor /proc/cpuinfo)
	cp "./.config" "/boot/config-$TARGET_KERNEL"

	time make bzImage -j"$CPU_COUNT"
	printf ":::::::make bzImage::::::::\n\n"

	time make modules -j"$CPU_COUNT"
	printf ":::::::make module::::::::\n\n"

	time make INSTALL_MOD_STRIP=1 modules_install
	printf ":::::::install module::::::::\n\n"

	time mkinitramfs "/lib/modules/$TARGET_KERNEL" -o "/boot/initrd.img-$TARGET_KERNEL"
	printf ":::::::mkinitramfs kernel::::::::\n\n"

	cp "arch/x86/boot/bzImage" "/boot/vmlinuz-$TARGET_KERNEL"
	cp "System.map" "/boot/System.map-$TARGET_KERNEL"

	update-grub2
	popd >/dev/null 2>&1 || exit 1
}

main() {
	set -e

	if ! check_apt; then
		printf "Only apt package manager is supported\n"
		exit 1
	fi

	VERSION="${1}"

	# check kernel version
	if [[ -z "${VERSION}" ]]; then
		printf "Please enter the kernel version\n"
		exit 1
	fi

	printf "Kernel %s will be installed\n\n" "${VERSION}"

	EXTRACT="linux-$VERSION"
	if [ ! -d "$EXTRACT" ]; then
		# download kernel package
		PACKAGE="$EXTRACT.tar.xz"
		if [ ! -f "$PACKAGE" ]; then
			DOWN_URL="${2}"
			if [ -z "$DOWN_URL" ]; then
				VER_FIRST=$(echo "$VERSION" | cut -d '.' -f 1)
				DOWN_URL="${MIRROR_URL}/v${VER_FIRST}.x/${PACKAGE}"
			fi
			curl -fsSL -o "$PACKAGE" "$DOWN_URL"
			printf "Download kernel %s from %s\n\n" "$VERSION" "$DOWN_URL"
		fi

		if [ ! -f "$PACKAGE" ]; then
			printf "\e[1;31mNo '%s' file found\e[0m\n" "$PACKAGE"
			exit 1
		fi

		tar -Jxf "$PACKAGE"
	fi

	if [ ! -d "$EXTRACT" ]; then
		printf "\e[1;31mThe '%s' folder was not found\e[0m\n" "$EXTRACT"
		exit 1
	fi

	install_deps || exit 1

	CURRENT_KERNEL=$(uname -r)
	TARGET_KERNEL="$VERSION-${CURRENT_KERNEL##*-}"
	printf "\nCurrent: \e[1;33m%s\e[0m ==> Target: \e[1;33m%s\e[0m\n\n" "$CURRENT_KERNEL" "$TARGET_KERNEL"

	do_upgrade "$@" 2>&1 | tee ./kernel.log
}

# 北外（下载速度最佳）
MIRROR_URL="https://mirrors.bfsu.edu.cn/kernel/"
# 阿里 https://mirrors.aliyun.com/linux-kernel/

main "$@" || exit 1
