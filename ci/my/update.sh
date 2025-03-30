#!/usr/bin/env bash

# 从 Git 仓库中拉取最新的代码

if [[ -n "${DEBUG:-}" ]]; then
  set -eux
else
  set -euo pipefail
fi

github_workflows() {
    git_url="${1:?"git_url is required"}"
    save_path="${2:?"save_path is required"}"

    if [[ "$save_path" == "." ]]; then
      save_path=""
    fi

    pushd golang > /dev/null 2>&1
    
    save_pre_path="./"
    if [[ -n "$save_path" ]]; then
      mkdir -p "$save_path"
      save_pre_path="./${save_path}/"
    fi
    
    for file in "${@:3}"; do
      save_file_path="${save_pre_path}${file}"
      fetch_file_path="${git_url}${save_path}/${file}"
      curl -fsSL -o "$save_file_path" "$fetch_file_path"
    done
    popd > /dev/null 2>&1
}

## Python

## Golang
git_url="https://framagit.org/idev/shortener/-/raw/main/"
file_list=(
  .goreleaser.yaml
  .hadolint.yaml
  justfile
  shortener.service
  docker-bake.hcl
)
github_workflows "$git_url" "." "${file_list[@]}"

save_path="deploy/docker"
file_list=(
  Dockerfile
  sqlite.compose.yml
)
github_workflows "$git_url" "$save_path" "${file_list[@]}"

file_list=(
  preinstall.sh
  postinstall.sh
  preremove.sh
  postremove.sh
)
scripts_path="scripts"
github_workflows "$git_url" "$scripts_path" "${file_list[@]}"

workflows_list=(
  docker-dev.yml
  docker-main.yml
  docker-release.yml
  release.yml
)
workflow_path=".github/workflows"
github_workflows "$git_url" "$workflow_path" "${workflows_list[@]}"

