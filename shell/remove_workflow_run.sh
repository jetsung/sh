#!/usr/bin/env bash

set -euo pipefail

# 检查参数
ORG_NAME=${1:?ORG_NAME is required}
REPO_NAME=${2:?REPO_NAME is required}
WORKFLOW_NAME=${3:?WORKFLOW_NAME is required}

# 定义常量
repo="$ORG_NAME/$REPO_NAME"
url="repos/$repo/actions/runs"
total_deleted=0

# 捕获脚本退出信号，输出总结信息
trap 'echo -e "\nTotal IDs deleted: $total_deleted"' EXIT

# 删除单个 ID 的函数
delete_id() {
  local id=$1
  echo "Deleting ID: $id"

  if gh api -X DELETE "$url/$id" --silent; then
    echo "✅: Deleted '$id'"
    ((total_deleted++)) || true  # 忽略算术表达式错误
  else
    echo "❌: Failed to delete '$id'"
    return 1
  fi
}

# 主循环
while true; do
  # 获取工作流运行数据
  runs=$(gh api "$url")

  # 提取 ID 列表
  ids=$(echo "$runs" | jq -r '.workflow_runs[].id')

  # 如果没有 ID 可删除，退出循环
  if [[ -z "$ids" ]]; then
    echo "No more IDs to delete."
    break
  fi

  # 遍历 ID 列表并删除
  while read -r id; do
    if ! delete_id "$id"; then
      echo "An error occurred. Exiting..."
      exit 1
    fi
  done <<< "$ids"

  # 可选：添加延迟以避免 API 速率限制
  # sleep 10
done

