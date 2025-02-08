#!/usr/bin/env bash

# ORIGIN: https://framagit.org/-/snippets/7413/raw/main/gitflydo.sh
#
# Description: 一台电脑上使用同一代码托管平台的多个 Git 账户
# Author: Jetsung Chan <jetsungchan@gmail.com>
# UpdatedAt: 2025-01-08

set -euo pipefail

judgment_parameters() {
    local HELP=""
    while [[ "$#" -gt '0' ]]; do
        case "$1" in

        '-t' | '--target')
            if [ -z "${2:?error: 请输入目标 Git 仓库地址}" ]; then
                exit 1
            fi
            TARGET_REPO_URL="$2"
            shift
            ;;

        '-o' | '--origin')
            if [ -z "${2:?error: 请输入源 Git 仓库地址}" ]; then
                exit 1
            fi
            ORIGIN_REPO_URL="$2"
            shift
            ;;

        '-c' | '--config')
            IS_CONFIG=1
            shift
            ;;

        '-h' | '--help')
            HELP='1'
            break
            ;;

        *)
            echo "$0: unknown option -- $1"
            exit 1
            ;;

        esac
        shift
    done

    if [ -n "$HELP" ]; then
        show_help
    fi
}

# 打印帮助信息
show_help() {
    echo "usage: $0 [ options ]"
    echo '  -t, --target    [TARGET_URL]   源仓库地址     示例: git@github.com:jetsung/sh.git'
    echo '  -o, --origin    [ORIGIN_URL]   目标仓库地址   示例: git@framagit.org:jetsung/sh.git'
    echo '  -c, --config                   是否配置用户信息'
    echo '  -h, --help                     打印帮助'
    exit 0
}

set_config() {
  if [ -n "$IS_CONFIG" ]; then
    git config user.name "$GIT_USERNAME"
    git config user.email "$GIT_EMAIL"
    
    git config user.signingkey "$IS_SIGNINGKEY"
    git config commit.gpgsign "$IS_GPGSIGN"
  fi
}

set_command() {
  if [ -f "$COMMAND_PATH" ]; then
    git config core.sshCommand "ssh -i $COMMAND_PATH"
  fi
}

init_remote() {
  if [ ! -d ".git" ]; then
    git init
  fi

  set_command
}

init_params() {
  ORIGIN_REPO_URL=""
  TARGET_REPO_URL=""
  IS_CONFIG=""

  # SSH KEY
  COMMAND_PATH="$HOME/.ssh/id_ed25519_flydo"

  # 用户信息
  GIT_USERNAME="Flydo Chen"
  GIT_EMAIL="flydochen@outlook.com"
  IS_SIGNINGKEY=""
  IS_GPGSIGN="false"
}

main() {
  init_params

  judgment_parameters "$@"

  if [ -n "$ORIGIN_REPO_URL" ]; then
    FOLDER_PRE="${ORIGIN_REPO_URL##*/}"
    FOLDER_DIR="${FOLDER_PRE%.*}"
    if [ ! -d "$FOLDER_DIR" ]; then
      mkdir "$FOLDER_DIR"
    fi
    cd "$FOLDER_DIR"

    init_remote

    git remote add origin "$ORIGIN_REPO_URL"
  else
    init_remote
  fi

  set_config

  if [ -n "${FOLDER_DIR:-}" ]; then
    git pull
    git checkout "$(git branch -a | awk -F '/' '{print $NF}' | head -n 1)"

    printf "\n\033[93mcd %s \033[0m\n" "$FOLDER_DIR"
  fi

  if [ -n "$TARGET_REPO_URL" ]; then
    git remote set-url origin "$TARGET_REPO_URL"
  fi
}

main "$@" || exit 1
