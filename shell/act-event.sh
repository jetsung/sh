#!/usr/bin/env bash

#============================================================
# File: act-event.sh
# Description: 生成 act 的 event.json 文件
# URL: https://s.fx4.cn/act-event
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-01
# UpdatedAt: 2025-08-26
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
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

ACT_BASE_IMAGE_PRE="# -P ubuntu-24.04=ghcr.io/catthehacker/ubuntu"

get_image_tags() {
  local OWNER="catthehacker"
  local PACKAGE="ubuntu"
  local FILTER="24.04"

  echo "Fetching ALL container image versions (this may take a while)..." >&2

  # # 若不存在 gh 命令
  # if ! command -v gh &> /dev/null; then
  #   echo "Error: 'gh' command not found. Please install 'gh' first." >&2
  #   exit 1
  # fi

  gh api \
    -H "Accept: application/vnd.github+json" \
    "/users/$OWNER/packages/container/$PACKAGE/versions" \
    --paginate \
    --jq '.[].metadata.container.tags[]' 2>/dev/null | \
    grep -E "\-$FILTER$" | \
    awk -v pre="$ACT_BASE_IMAGE_PRE" '{print pre":"$0}' | \
    sort -u >> .actrcs
  }

save_image_tags() {
  local tags=(
    custom-24.04
    js-24.04
    java-tools-24.04
    rust-24.04
    pwsh-24.04
    go-24.04
    gh-24.04
    dotnet-24.04
    runner-24.04
    act-24.04
    full-24.04    
  )

  # -P ubuntu-24.04=ghcr.io/catthehacker/ubuntu:act-24.04
  for tag in "${tags[@]}"; do
    echo "${ACT_BASE_IMAGE_PRE}:${tag}" >> .actrcs
  done
}

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

# 取出 name
repo_name=$(echo "$full_name" | awk -F '/' '{print $2}')

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
  --arg repo_name "$repo_name" \
  --arg commit_id "$commit_id" \
  --arg commit_message "$commit_message" \
  --arg timestamp "$timestamp" \
  --arg author_name "$author_name" \
  --arg author_email "$author_email" \
  '{
    "ref": $ref,
    "before": $before,
    "after": $after,
    "inputs": {},
    "repository": {
      "full_name": $full_name,
      "name": $repo_name,
      "owner": {
        "login": $pusher_name
      }
    },
    "pusher": {
        "name": $pusher_name
    },
    "head_commit": {
        "id": $commit_id,
        "message": $commit_message,
        "timestamp": $timestamp,
        "author": {
            "name": $author_name,
            "email": $author_email
        }
    },
    "action": "created",
    "release": {
        "tag_name": "",
        "name": "",
        "draft": false,
        "prerelease": false
    }
}' > event.json

echo "已写入 event.json：ref=$ref, full_name=$full_name"

if [[ ! -f .gitignore ]]; then
  touch .gitignore
fi

# 判断 .gitignore 如果没有忽略。则写入忽略
if ! grep -q '# act' .gitignore; then
    echo "" >> .gitignore
    echo '# act' >> .gitignore
fi
if ! grep -q '.actenv' .gitignore; then
    echo '.actenv' >> .gitignore
fi
if ! grep -q '.actrc' .gitignore; then
    echo '.actrc' >> .gitignore
fi
if ! grep -q '.actrcs' .gitignore; then
    echo '.actrcs' >> .gitignore
fi
if ! grep -q '.artifacts' .gitignore; then
    echo '.artifacts' >> .gitignore
fi
if ! grep -q '.secrets' .gitignore; then
    echo '.secrets' >> .gitignore
fi
if ! grep -q 'event.json' .gitignore; then
    echo 'event.json' >> .gitignore
fi
echo "" >> .gitignore

# 判断若存在 .actrc 文件则不执行
if [[ ! -f .actrcs ]]; then
  if [[ -n "${GITHUB_TOKEN:-}" ]] && command -v gh; then
    get_image_tags
  else
    save_image_tags
  fi
fi

echo "GITHUB_REPOSITORY=$full_name" > .actenv
echo "GITHUB_TOKEN=$GITHUB_TOKEN" >> .secrets

echo "act -e event.json --secret-file .secrets --env-file .actenv --artifact-server-path ./.artifacts"

# ###
# #      基础镜像：https://github.com/catthehacker/docker_images/pkgs/container/ubuntu
# #      示例： curl -L https://s.fx4.cn/JRlgxD | bash -s -- dev forkdo/vsd
# ###
# #      触发分支：act push -e event.json --secret-file .secrets --env-file .actenv --artifact-server-path ./.artifacts
# #         发布：act release -e event.json
# #               --env GITHUB_REPOSITORY=jetsung/rclone-backup
# ###
