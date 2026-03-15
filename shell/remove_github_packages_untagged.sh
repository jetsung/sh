#!/usr/bin/env bash

#============================================================
# File: remove_github_packages_untagged.sh
# Description: 删除 GitHub Packages 悬空的镜像标签
# URL: https://fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/githubci/raw/HEAD/remove_github_packages_untagged.sh
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-18
# UpdatedAt: 2025-08-18
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 配置
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
ORG_NAME="${1:?ORG_NAME is required}"    # 组织名称；若为个人账号可传 '-'，此时使用 "users/"
REPO_NAME="${2:?REPO_NAME is required}"  # 包所属的仓库名称

if [ "$ORG_NAME" = "-" ]; then
  ORG_INFO="user/"
else
  ORG_INFO="orgs/$ORG_NAME/"
fi

page=1
while true; do
  echo "Fetching page $page of package versions..."
  versions_json=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/${ORG_INFO}packages/container/$REPO_NAME/versions?per_page=100&page=$page")

  count=$(echo "$versions_json" | jq 'length')
  if [ "$count" -eq 0 ]; then
    echo "No more package versions to process."
    break
  fi

  echo "Processing $count versions on page $page..."
  # 遍历当前页面所有版本（使用 base64 避免 jq 中处理特殊字符问题）
  for version_enc in $(echo "$versions_json" | jq -r '.[] | @base64'); do
    # 定义一个辅助函数，便于解码 JSON 字段
    _jq() {
      echo "$version_enc" | base64 --decode | jq -r "${1}"
    }

    version_id=$(_jq '.id')
    tag_count=$(_jq '.metadata.container.tags | length')

    if [ "$tag_count" -eq 0 ]; then
      echo "Deleting untagged version: $version_id"
      http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/${ORG_INFO}packages/container/$REPO_NAME/versions/$version_id")
      if [ "$http_code" -eq 204 ]; then
        echo "Deleted version $version_id successfully."
      else
        echo "Failed to delete version $version_id. HTTP status: $http_code"
      fi
    else
      echo "Skipping version $version_id (tag count: $tag_count)"
    fi
  done

  page=$((page + 1))
done

echo "Done."
