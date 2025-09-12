#!/usr/bin/env bash

#============================================================
# File: shell.sh
# Description: 将命令行组合成函数调用
# URL: https://s.fx4.cn/shell
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-09-12
# UpdatedAt: 2025-09-12
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

USER_ID="$(id -u)"

sudo_exec() {
    if [[ "$USER_ID" -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

main() {
    _command="${1:?Error: Missing parameter 1.}"
    shift

    $_command "$@"
}

# 设置默认编辑器为 vim
editor() {
    # 获取 vim.basic 对应的编号
    editor_choice=$(sudo_exec update-alternatives --config editor 2>&1 | grep -n "vim.basic" | head -n 1 | sed 's/^[[:space:]]*//' | awk '{print $2}')

    # 如果找到了 vim.basic，自动选择该编号
    if [ -n "$editor_choice" ]; then
        echo "$editor_choice" | sudo update-alternatives --config editor
        echo
        echo "editor_choice: $editor_choice"
        echo
    else
        echo "vim.basic not found in alternatives."
    fi
}

# 安装 uv
uv() {
    curl -L https://s.fx4.cn/x | bash -s -- https://s.fx4.cn/uv | bash
}

main "$@"
