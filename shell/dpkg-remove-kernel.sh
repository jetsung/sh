#!/usr/bin/env bash

###
## Ubuntu 移除多余内核
###

get_versions() {
	OLD_VERSION=$(uname -r)
	VERSIONS=$(dpkg --get-selections | grep linux-image-5. | awk '{print $1}' | cut -d - -f 3,4,5)
}

remove_kernel() {
	for VER in "$@"; do
		if [ "${OLD_VERSION}" != "${VER}" ]; then
			printf "\n\nRemove Kernel: %s\n" "${VER}"

			# 删除内核
			dpkg --get-selections | grep "${VER}" | awk '{print $1}' | xargs apt remove -y

			# 移除 deinstall 标识的信息
			dpkg --get-selections | grep linux | grep deinstall | awk '{print $1}' | xargs dpkg -P
		fi
	done
}

main() {
	get_versions

	remove_kernel "$VERSIONS"
}

main "$@" || exit 1
