#!/usr/bin/env bash

#============================================================
# File: remove_gitlab_workflow_runs.sh
# Description: 批量删除 GitLab CI 流水线
# URL: https://fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/gitlabci/raw/HEAD/remove_gitlab_workflow_runs.sh
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

project_path="$ORG_NAME/$REPO_NAME"
encoded_path=$(echo -n "$project_path" | jq -sRr @uri)
url="projects/$encoded_path/pipelines"

total_deleted=0

#GITLAB_HOST=""

delete_pipeline() {
  local id=$1
  local result=""

  echo "Deleting pipeline ID: $id"
  if glab api --method DELETE "$url/$id" --silent; then
    result="✅ Deleted pipeline '$id'"
    total_deleted=$((total_deleted + 1))
  else
    result="❌ Failed to delete pipeline '$id'"
    echo "$result"
    echo "An error occurred while deleting pipeline ID '$id'. Press Enter to exit."
    echo "Total pipelines deleted: $total_deleted"
    read -n 1 -s -r -p ""
    exit 1
  fi

  printf "%s\n" "$result"
}

while true; do
  # 获取流水线列表（默认每页20条）
  response=$(glab api "$url" --paginate 2>/dev/null || echo "[]")
  total_pipelines=$(echo "$response" | jq '. | length')

  if [[ $total_pipelines -eq 0 ]]; then
    echo "No more pipelines to delete. Press Enter to exit."
    echo "Total pipelines deleted: $total_deleted"
    read -n 1 -s -r -p ""
    break
  fi

  # 使用 process substitution 避免子 shell
  while read -r id; do
    id="${id//$'\r'/}"   # 去掉回车符
    delete_pipeline "$id"
  done < <(echo "$response" | jq -r '.[].id')

  # 可选：等待几秒再继续循环，避免频繁调用 API
  # sleep 2
done
