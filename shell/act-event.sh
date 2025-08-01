#!/usr/bin/env bash

#============================================================
# File: act-event.sh
# Description: 生成 act 的 event.json 文件
# URL: https://s.fx4.cn/JRlgxD
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-01
# UpdatedAt: 2025-08-01
#============================================================

if [[ -n "$DEBUG" ]]; then
    set -eux
else
    set -euo pipefail
fi

usage() {
  cat <<EOF
用法: $0 <branch> <full_name>
例如: $0 dev idev-sig/file-downloader
EOF
  exit 1
}

if [ $# -lt 2 ]; then
  usage
fi

branch=$1
full_name=$2

# 可修改的固定值
before="0000000000000000000000000000000000000000"
after="1111111111111111111111111111111111111111"
pusher_name="jetsung"
commit_id="$after"
commit_message="Test commit"
timestamp="2025-07-31T12:00:00Z"
author_name="test"
author_email="test@gmail.com"

ref="refs/heads/${branch}"

# 需要 jq 生成安全的 JSON
if ! command -v jq >/dev/null 2>&1; then
  echo "错误：本脚本依赖 jq，请先安装 jq。" >&2
  exit 2
fi

jq -n \
  --arg ref "$ref" \
  --arg before "$before" \
  --arg after "$after" \
  --arg full_name "$full_name" \
  --arg pusher_name "$pusher_name" \
  --arg commit_id "$commit_id" \
  --arg commit_message "$commit_message" \
  --arg timestamp "$timestamp" \
  --arg author_name "$author_name" \
  --arg author_email "$author_email" \
  '{
    ref: $ref,
    before: $before,
    after: $after,
    repository: { full_name: $full_name },
    pusher: { name: $pusher_name },
    head_commit: {
      id: $commit_id,
      message: $commit_message,
      timestamp: $timestamp,
      author: { name: $author_name, email: $author_email }
    }
  }' > event.json

echo "已写入 event.json：ref=$ref, full_name=$full_name"
