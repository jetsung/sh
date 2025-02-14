#!/usr/bin/env bash

###
## Ubuntu 移除多余内核
###

get_current_version() {
	uname -r | cut -d '-' -f 1,2
}

remove_otherk_kernel() {
	while read -r line; do
		package=$(echo "$line" | awk '{print $1}')
		kernel_version=$(echo "$package" | cut -d '-' -f 3,4)
		if [ -z "$kernel_version" ]; then
			continue
		fi

		if [[ "$kernel_version" != "$current_version"* ]]; then
			# echo "Remove Kernel: $package"
			sudo apt remove -y "$package"
		fi
	done <<< "$(dpkg --get-selections | grep -E 'linux-headers-[0-9]|linux-image-[0-9]|linux-modules-[0-9]|linux-tools-[0-9]')"
	
	sudo apt autoremove -y
}

# 移除 deinstall 标识的信息
remove_deinstall_flag() {
	dpkg --get-selections | grep deinstall | awk '{print $1}' | xargs sudo dpkg -P	
}

main() {
	current_version=$(get_current_version)
	echo "Current version: $current_version"

	remove_otherk_kernel "$current_version"
	remove_deinstall_flag
}

main "$@" || exit 1
