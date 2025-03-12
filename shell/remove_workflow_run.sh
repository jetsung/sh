#!/usr/bin/env bash

set -euo pipefail

# 检查参数
ORG_NAME=${1:?ORG_NAME is required}
REPO_NAME=${2:?REPO_NAME is required}

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

main() {
  # 获取工作流运行数据
  runs=$(gh api "$url")

  # 提取 ID 列表
  mapfile -t ids < <(echo "$runs" | jq -r '.workflow_runs[].id')

  # 获取数组长度
  total_ids=${#ids[@]}

  # 如果没有 ID 可删除，退出脚本
  if (( total_ids == 0 )); then
    echo "No workflow runs found to delete."
    exit 0
  fi

  # 获取最新的一个 ID（假设 ID 越大表示越新）
  # latest_id="${ids[$total_ids - 1]}"

  # 遍历 ID 列表并删除，保留最新的一个
  for (( i=0; i<total_ids; i++ )); do
    id="${ids[$i]}"
    if ! delete_id "$id"; then
      echo "An error occurred while deleting ID $id. Exiting..."
      exit 1
    fi
  done

}

main "$@"