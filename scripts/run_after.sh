#!/usr/bin/env bash

set -euo pipefail

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