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
before=$(git rev-parse HEAD)
after=$(head -c 20 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-40)
pusher_name="jetsung"
commit_id="$after"
commit_message="chore(ci): Test act commit"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
author_name="Jetsung Chan"
author_email="jetsungchan@gmail.com"

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
    },
    "action": "created",
    "release": {
      "tag_name": "v0.0.99",
      "name": "v0.0.99",
      "draft": false,
      "prerelease": false
    }
  }' > event.json

echo "已写入 event.json：ref=$ref, full_name=$full_name"

# 判断 .gitignore 如果没有忽略。则写入忽略
if ! grep -q '# act' .gitignore; then
    echo '# act' >> .gitignore
fi
if ! grep -q '.actrc' .gitignore; then
    echo '.actrc' >> .gitignore
fi
if ! grep -q '.artifacts' .gitignore; then
    echo '.artifacts' >> .gitignore
fi
if ! grep -q 'event.json' .gitignore; then
    echo 'event.json' >> .gitignore
fi
if ! grep -q '.secrets' .gitignore; then
    echo '.secrets' >> .gitignore
fi
if ! grep -q '.arcenv' .gitignore; then
    echo '.arcenv' >> .gitignore
fi

###
#      基础镜像：https://github.com/catthehacker/docker_images/pkgs/container/ubuntu
#      示例： curl -L https://s.fx4.cn/JRlgxD | bash -s -- dev forkdo/vsd
###
#      触发分支：act push -e event.json --secret-file .secrets --env-file .env --artifact-server-path ./.artifacts
#         发布：act release -e event.json
###
