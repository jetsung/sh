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

save_path=".github/workflows"
file_list=(
  docker-dev.yml
  docker-main.yml
  docker-release.yml
  release.yml
  golangci-lint.yml
)
github_workflows "$git_url" "$save_path" "${file_list[@]}"

save_path="deploy/docker"
file_list=(
  Dockerfile
  compose.yml
)
github_workflows "$git_url" "$save_path" "${file_list[@]}"

save_path="scripts"
file_list=(
  preinstall.sh
  postinstall.sh
  preremove.sh
  postremove.sh
)
github_workflows "$git_url" "$save_path" "${file_list[@]}"

save_path="."
file_list=(
  .github/dependabot.yml
  .golangci.yml
  .goreleaser.yaml
  .hadolint.yaml
  .rest
  justfile
  docker-bake.hcl
  openapi.yml
  shortener.service
)
github_workflows "$git_url" "$save_path" "${file_list[@]}"
