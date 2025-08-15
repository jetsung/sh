#!/usr/bin/env bash

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

do_install_list() {
    pushd "$1" > /dev/null 2>&1
    rm -rf list.txt
    find . -maxdepth 1 -type f -name '*.sh' | sort | while read -r file; do
        title=$(grep -m1 '^# Description:' "$file" | cut -d':' -f2- | xargs)
        if [[ -n "$title" ]]; then
            echo "$file  |  $title" >> list.txt
        else
            echo "$file" >> list.txt
        fi
    done
    popd > /dev/null 2>&1
}

update_readme() {
    pushd "$1" > /dev/null 2>&1
    
    # 删除 |:---| 行之后的所有内容
    sed -i -n '1,/|:---|/p' README.md

    (
    for file in *.sh; do
        if [[ -f "$file" ]]; then
            _file_no_ext="${file%%.*}"
            _desc=$(grep -m1 '^# Description:' "$file" | cut -d':' -f2- | xargs)  # 提取标题
            _url=$(grep -m1 '^# URL:' "$file" | cut -d':' -f2- | xargs)  # 提取标题

            url_str=""
            if [[ -n "$_url" ]]; then
                url_str="[${_url}](${_url})"
            fi

            echo "| [**${_file_no_ext}**](${file}) | ${url_str} | ${_desc} |"
        fi
    done
    ) >> README.md

    popd > /dev/null 2>&1
}

do_dir() {
    if [[ -d "$1" ]]; then
        do_install_list "$1"
        update_readme "$1"
    fi
}

main() {
    do_dir "build"
    do_dir "install"
}

main "$@"