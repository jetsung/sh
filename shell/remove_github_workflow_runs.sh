#!/usr/bin/env bash

#============================================================
# File: remove_github_workflow_runs.sh
# Description: 批量删除 GitHub Action Workflows 流水线
# URL: https://s.fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/githubci/raw/HEAD/remove_github_workflow_runs.sh
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

ORG_NAME=${1:?ORG_NAME is required}
REPO_NAME=${2:?REPO_NAME is required}

repo="$ORG_NAME/$REPO_NAME"
url="repos/$repo/actions/runs"

total_deleted=0

delete_id() {
  local id=$1
  local result=""

  echo "Deleting URL: $url/$id"
  if gh api -X DELETE "$url/$id" --silent; then
    result="✅ Deleted '$id'"
    total_deleted=$((total_deleted + 1))
  else
    result="❌ Failed '$id'"
    echo "$result"
    echo "An error occurred while deleting ID '$id'. Press Enter to exit."
    echo "Total IDs deleted: $total_deleted"
    read -n 1 -s -r -p ""
    exit 1
  fi

  printf "%s\n" "$result"
}

while true; do
  total_ids=$(gh api "$url" | jq '.workflow_runs | length')

  if [[ $total_ids -eq 0 ]]; then
    echo "No more IDs to delete. Press Enter to exit."
    echo "Total IDs deleted: $total_deleted"
    read -n 1 -s -r -p ""
    break
  fi

  # 使用 process substitution 避免子 shell
  while read -r id; do
    id="${id//$'\r'/}"   # 去掉回车符
    delete_id "$id"
  done < <(gh api "$url" | jq -r '.workflow_runs[].id')

  # 可选：等待几秒再继续循环，避免频繁调用 API
  # sleep 2
done
