#!/usr/bin/env bash

#============================================================
# File: remove_github_packages_untagged.sh
# Description: 删除 GitHub Packages 镜像版本（默认仅 untagged，--all 含 tagged）
# URL: https://fx4.cn/
# OpenGist: https://gist.asfd.cn/jetsung/githubci/raw/HEAD/remove_github_packages_untagged.sh
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.0
# CreatedAt: 2025-08-18
# UpdatedAt: 2025-09-29
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 配置
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

# 用法: remove_github_packages_untagged.sh [--all|-a] <org>/<repo> | <org> <repo>
#   --all / -a: 删除全部版本（含 tagged），默认仅删 untagged
# 参数归一化: 支持
DELETE_ALL=0
declare -a pos_args=()
for _a in "$@"; do
  case "$_a" in
    --all|-a) DELETE_ALL=1 ;;
    *) pos_args+=("$_a") ;;
  esac
done

arg1="${pos_args[0]:?ORG_NAME or package identifier is required}"
arg2="${pos_args[1]:-}"

case "$arg1" in
  https://github.com/*/pkgs/container/* | http://github.com/*/pkgs/container/* )
    pkg="${arg1#*://github.com/}"
    pkg="${pkg%/pkgs/container/*}"
    pkg="${pkg%.git}"
    ORG_NAME="${pkg%%/*}"
    REPO_NAME="${pkg#*/}"
    ;;
  https://github.com/* | http://github.com/* | git://github.com/* )
    pkg="${arg1#*://github.com/}"
    pkg="${pkg%.git}"
    ORG_NAME="${pkg%%/*}"
    REPO_NAME="${pkg#*/}"
    ;;
  git@github.com:* )
    pkg="${arg1#git@github.com:}"
    pkg="${pkg%.git}"
    ORG_NAME="${pkg%%/*}"
    REPO_NAME="${pkg#*/}"
    ;;
  ghcr.io/* )
    pkg="${arg1#ghcr.io/}"
    pkg="${pkg%/}"
    pkg="${pkg%.git}"
    ORG_NAME="${pkg%%/*}"
    REPO_NAME="${pkg#*/}"
    ;;
  */* )
    ORG_NAME="${arg1%%/*}"
    REPO_NAME="${arg1#*/}"
    ;;
  * )
    ORG_NAME="$arg1"
    REPO_NAME="${arg2:?REPO_NAME is required}"
    ;;
esac

if [ "$ORG_NAME" = "-" ]; then
  ORG_INFO="user/"
else
  ORG_INFO="orgs/$ORG_NAME/"
fi

total_deleted=0
per_page=100
api_base="https://api.github.com/${ORG_INFO}packages/container/$REPO_NAME/versions"

# 该接口返回数组（无 total_count），逐页推进；
# 删除某版本后后续版本前移，故删后留在当前页重拉，避免漏删。
page=1
while true; do
  echo "Fetching page $page of package versions..."
  versions_json=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "$api_base?per_page=$per_page&page=$page")

  count=$(echo "$versions_json" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    echo "No more package versions to process."
    break
  fi

  echo "Processing $count versions on page $page..."
  deleted_in_page=0

  # 遍历当前页面所有版本（使用 base64 避免 jq 处理特殊字符问题）
  for version_enc in $(echo "$versions_json" | jq -r '.[] | @base64'); do
    # 解码 JSON 字段
    _jq() {
      echo "$version_enc" | base64 --decode | jq -r "${1}"
    }

    version_id=$(_jq '.id')
    tag_count=$(_jq '.metadata.container.tags | length')

    if [[ "$DELETE_ALL" -eq 1 || "$tag_count" -eq 0 ]]; then
      if [[ "$tag_count" -gt 0 ]]; then
        tags=$(_jq '.metadata.container.tags | join(", ")')
        echo "Deleting tagged version: $version_id (tags: $tags)"
      else
        echo "Deleting untagged version: $version_id"
      fi
      http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "$api_base/$version_id")
      if [[ "$http_code" -eq 204 ]]; then
        echo "Deleted version $version_id successfully."
        total_deleted=$((total_deleted + 1))
        deleted_in_page=$((deleted_in_page + 1))
      else
        echo "Failed to delete version $version_id. HTTP status: $http_code"
      fi
    else
      echo "Skipping version $version_id (tag count: $tag_count)"
    fi
  done

  # 本页有删除 -> 后续版本前移，重拉本页；无删除 -> 推进下一页
  if [[ "$deleted_in_page" -gt 0 ]]; then
    echo "Page $page: deleted $deleted_in_page, re-fetching same page."
  else
    page=$((page + 1))
  fi
done

echo "Done. Total $([ "$DELETE_ALL" -eq 1 ] && echo 'all' || echo 'untagged') versions deleted: $total_deleted"
