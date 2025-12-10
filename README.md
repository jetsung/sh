# My Scripts

我的脚本文件

## 目录列表

```bash
├── build      # 编译安装软件脚本
├── ci         # CI/CD脚本
├── dockerfile # Dockerfile
├── conf       # 软件配置文件
├── init.d     # 软件启动文件
├── install    # 二进制软件安装脚本
├── origin     # 脚本源
├── pwsh       # 自己编写的 PowerShell 脚本
├── python     # 自己编写的 Python 脚本
├── shell      # 自己编写的 Shell 脚本
└── softs      # 自己编写的一些提取软件版本号和下载地址的脚本 
└── commit.sh  # 提交前执行生成新的 list.txt
└── fetch.sh   # 从云端更新脚本至本地
```

## 先决条件

```bash
sudo apt install -y jq
```

## 从云端下载并更新对应的 `.sh` 脚本文件
执行 `scripts/fetch.sh` 文件。若 `.sh` 的文件中包含下述注释，则拉取更新
```bash
# ORIGIN: https://myfiles.com/origin-file.sh
```

## SHELL 文件格式
```shell
#!/usr/bin/env bash

#============================================================
# File: file.sh
# Description: 
# URL: https://fx4.cn/
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-
# UpdatedAt: 2025-
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

USER_ID="$(id -u)"

sudo_exec() {
    if [[ "$USER_ID" -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

check_is_command() {
    command -v "$1" >/dev/null 2>&1
}

check_in_china() {
    if [[ -n "${CN:-}" ]]; then
        return 0 # 手动指定
    fi
    if [[ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" == "000" ]]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}

# 若为 https://xxx.xx 不以 / 结尾，则组合时去掉加速网址的 https://
#   格式为 https://file.xxx.io/github.com/
# 若为 https://xxx.xx/ 以 / 结尾，则组合时保留加速网址的 https://
#   格式为 https://xxx.xx/https://github.com/
check_remove_https() {
    if [[ -n "$1" && "${1: -1}" != "/" ]]; then
        echo 1
    fi    
}

do_remove_https() {
    local url="$1"
    if [[ -n "$NO_HTTPS" ]]; then
        # shellcheck disable=SC2001
        echo "$url" | sed 's|https:/||2'

    else 
        echo "$url"
    fi
}

########################## 以上为通用函数 #########################
```

## 仓库镜像

 [**MyCode**](https://git.jetsung.com/jetsung/sh) ● [**Framagit**](https://framagit.org/jetsung/sh) ● [**GitCode**](https://gitcode.com/jetsung/sh) ● [**GitHub**](https://github.com/jetsung/sh)
