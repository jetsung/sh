#!/usr/bin/env bash

#============================================================
# File: remove_github_workflow_runs.sh
# Description: 批量删除 GitHub Action Workflows 流水线
# URL: https://fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/githubci/raw/HEAD/remove_github_workflow_runs.sh
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.0
# CreatedAt: 2025-08-18
# UpdatedAt: 2025-08-18
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

if [[ "${1:-}" == */* ]]; then
  ORG_NAME="${1%%/*}"
  REPO_NAME="${1#*/}"
else
  ORG_NAME=${1:?ORG_NAME is required}
  REPO_NAME=${2:?REPO_NAME is required}
fi

repo="$ORG_NAME/$REPO_NAME"
url="repos/$repo/actions/runs"

total_deleted=0

delete_id() {
  local id=$1

  echo "Deleting URL: $url/$id"
  if gh api -X DELETE "$url/$id" --silent; then
    printf "✅ Deleted '%s'\n" "$id"
    total_deleted=$((total_deleted + 1))
  else
    printf "⚠️  Skipped '%s' (可能正在运行)\n" "$id"
  fi
}

while true; do
  api_result=$(gh api "$url?per_page=100" 2>/dev/null)
  total_count=$(echo "$api_result" | jq '.total_count')

  if [[ $total_count -eq 0 ]]; then
    echo "No more IDs to delete. Total IDs deleted: $total_deleted"
    break
  fi

  per_page=100
  total_pages=$(( (total_count + per_page - 1) / per_page ))

  deleted_before=$total_deleted

  page=$total_pages
  while [[ $page -ge 1 ]]; do
    while read -r id; do
      id="${id//$'\r'/}"
      delete_id "$id"
    done < <(gh api "$url?per_page=$per_page&page=$page" 2>/dev/null | jq -r '[.workflow_runs[].id] | reverse | .[]')

    page=$((page - 1))
  done

  if [[ $total_deleted -eq $deleted_before ]]; then
    echo "本轮无可删除的 run（可能都在运行中），退出。Total IDs deleted: $total_deleted"
    break
  fi
done
