#!/usr/bin/env bash

#============================================================
# File: remove_github_workflow_runs.sh
# Description: 批量删除 GitHub 部署记录
# URL: https://s.fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/githubci/raw/HEAD/remove_github_deployments_run.sh
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

owner="$1"  # 替换为仓库所有者的用户名
repo="$2"       # 替换为仓库名称

# 获取所有部署记录的 ID，按创建时间降序排列
deployment_ids=$(gh api "repos/$owner/$repo/deployments" --paginate --jq 'sort_by(.created_at) | reverse | .[].id')

# 将部署 ID 保存到数组中
readarray -t ids <<<"$deployment_ids"

# 获取部署记录的数量
num_deployments=${#ids[@]}

# 如果部署记录少于2个，则无需删除
if [[ "$num_deployments" -lt 2 ]]; then
  echo "没有足够的部署记录可供删除。"
  exit 0
fi

# 遍历部署 ID，跳过最新的一个
for ((i=1; i<num_deployments; i++)); do
  deployment_id=${ids[i]}
  echo "删除部署 ID: $deployment_id"
  if ! gh api -X DELETE "repos/$owner/$repo/deployments/$deployment_id" --silent; then
    echo "失败"
  fi
done

echo "旧的部署记录已删除，仅保留最新的一个。"
