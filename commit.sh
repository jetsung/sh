#!/usr/bin/env bash

###
#
# git commit 前执行，更新对应脚本中的 list.txt 文件列表
#
###

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

do_install_list() {
    pushd "$1" > /dev/null 2>&1
    rm -rf list.txt
    find . -maxdepth 1 -type f \( -name "*.sh" -o -name "*.ps1" -o -name "*.py" \) -not -wholename "./.upgrade.sh" -print0 | sort |
    while IFS= read -r -d '' file; do    
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
    # 查找所有符合条件的脚本文件，支持空格和特殊字符
    find . -maxdepth 1 -type f \( -name "*.sh" -o -name "*.ps1" -o -name "*.py" \) -print0 | sort |
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            _file_with_ext="${file##*/}"  # 提取文件名（包括扩展名）
            _file_no_ext="${_file_with_ext%.*}"  # 去除扩展名
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
    dir_list=(
        build
        install
        pwsh
        python
        shell
    )

    for dir in "${dir_list[@]}"; do
        do_dir "$dir"
    done
}

main "$@"
