#!/usr/bin/env bash

set -euo pipefail

do_install_list() {
    pushd install > /dev/null 2>&1
    rm -rf list.txt
    for file in *.sh; do
        if [[ -f "$file" ]]; then
            title=$(grep -m1 '^# Description:' "$file" | cut -d':' -f2- | xargs)  # 提取标题
            if [[ -n "$title" ]]; then
                echo "$file  |  $title" >> list.txt
            else
                echo "$file" >> list.txt  # 处理无 description 的情况
            fi
        fi
    done
    popd > /dev/null 2>&1
}

do_install_readme() {
    pushd install > /dev/null 2>&1
    
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

main() {
    # 处理 install 文件夹
    do_install_list
    do_install_readme
}

main "$@"