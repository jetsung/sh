#!/usr/bin/env bash

#============================================================
# File: docker-compose.sh
# Description: 从 Git 仓库下载 docker-compose 相关文件
# URL: https://fx4.cn/dservice
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-06-21
# UpdatedAt: 2026-06-21
#============================================================

if [[ -n "$DEBUG" ]]; then
  set -eux
else
  set -euo pipefail
fi

# 基础 URL
GIT_REPO_GITHUB="https://github.com/jetsung/awesome-compose/raw/refs/heads/main/%s/%s"
GIT_REPO_GITEA="https://git.asfd.cn/jetsung/awesome-compose/raw/branch/main/%s/%s"
GIT_REPO_ATOMGIT="https://raw.atomgit.com/jetsung/awesome-compose/raw/main/%s/%s"

# 文件列表（按序号排列）
FILE_LIST=(
  compose.yaml
  .env
  compose.override.yaml
  README.md
  backup.sh
)

# 默认值
FILE_COUNT=2
SOURCE="github"
BACKUP="no"
SAVE_DIR=""

# 使用说明
usage() {
  cat <<EOF
用法: $(basename "$0") -s SERVICE_NAME [选项]

必填参数:
  -s SERVICE_NAME    服务名

可选参数:
  -n FILE_COUNT      下载文件数量 1-5（默认: 2）
                     1: compose.yaml
                     2: compose.yaml + .env
                     3: compose.yaml + .env + compose.override.yaml
                     4: compose.yaml + .env + compose.override.yaml + README.md
                     5: compose.yaml + .env + compose.override.yaml + README.md + backup.sh
  -r SOURCE          下载源: github | gitea | atomgit（默认: github）
  -d SAVE_DIR        保存目录（默认: 以服务名命名的文件夹）
                     传入 "." 时保存到当前目录
  -b                 下载 backup.sh（若 FILE_COUNT 已包含则忽略）
  -h                 显示帮助信息

示例:
  $(basename "$0") -s nginx
  $(basename "$0") -s nginx -n 3
  $(basename "$0") -s nginx -n 4 -r gitea
  $(basename "$0") -s nginx -d .
  $(basename "$0") -s nginx -b
EOF
  exit 0
}

# 解析参数
SERVICE_NAME=""
while getopts "s:n:r:d:bh" opt; do
  case $opt in
    s) SERVICE_NAME="$OPTARG" ;;
    n) FILE_COUNT="$OPTARG" ;;
    r) SOURCE="$OPTARG" ;;
    d) SAVE_DIR="$OPTARG" ;;
    b) BACKUP="yes" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# 参数检查
if [[ -z "$SERVICE_NAME" ]]; then
  echo "错误: 必须指定服务名 (-s)"
  usage
fi

# 验证 FILE_COUNT
if ! [[ "$FILE_COUNT" =~ ^[1-5]$ ]]; then
  echo "错误: FILE_COUNT 必须是 1-5 之间的整数"
  exit 1
fi

# 验证 SOURCE
case "$SOURCE" in
  github|gitea|atomgit) ;;
  *)
    echo "错误: SOURCE 必须是 github、gitea 或 atomgit"
    exit 1
    ;;
esac

# 选择基础 URL
case "$SOURCE" in
  github) BASE_URL="$GIT_REPO_GITHUB" ;;
  gitea)  BASE_URL="$GIT_REPO_GITEA" ;;
  atomgit) BASE_URL="$GIT_REPO_ATOMGIT" ;;
esac

# 构建需要下载的文件列表
DOWNLOAD_FILES=()
for ((i=0; i<FILE_COUNT; i++)); do
  DOWNLOAD_FILES+=("${FILE_LIST[$i]}")
done

# 如果 BACKUP=yes 且 backup.sh 不在列表中，则添加
if [[ "$BACKUP" == "yes" ]]; then
  has_backup=false
  for file in "${DOWNLOAD_FILES[@]}"; do
    if [[ "$file" == "backup.sh" ]]; then
      has_backup=true
      break
    fi
  done
  if [[ "$has_backup" == "false" ]]; then
    DOWNLOAD_FILES+=(backup.sh)
  fi
fi

# 确定保存目录
if [[ -z "$SAVE_DIR" ]]; then
  TARGET_DIR="$SERVICE_NAME"
elif [[ "$SAVE_DIR" == "." ]]; then
  TARGET_DIR="."
else
  TARGET_DIR="$SAVE_DIR"
fi

mkdir -p "$TARGET_DIR"

# 下载文件
for file in "${DOWNLOAD_FILES[@]}"; do
  # shellcheck disable=SC2059
  URL=$(printf "$BASE_URL" "$SERVICE_NAME" "$file")
  echo "下载: $file"
  if curl -fsSL -o "$TARGET_DIR/$file" "$URL"; then
    echo "  完成: $TARGET_DIR/$file"
  else
    echo "  失败: $file 不存在或下载出错"
    rm -f "$TARGET_DIR/$file"
  fi
done

echo ""
echo "完成! 文件已下载到 $TARGET_DIR/"
