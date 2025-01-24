#!/usr/bin/env bash

# ORIGIN: https://framagit.org/-/snippets/7149/raw/main/mirror.sh

#set -eux

UPSTREAM_REPO_LIST=()
if [[ -n "${REPO:-}" ]]; then
        IFS=','
        read -ra repo_list <<<"$REPO"
        UPSTREAM_REPO_LIST=("${repo_list[@]}")
elif [[ -n "${2:-}" ]]; then
        IFS=','
        read -ra repo_list <<<"$2"
        UPSTREAM_REPO_LIST=("${repo_list[@]}")
elif [[ -f list.txt ]]; then
        while IFS= read -r line; do
                if [[ $line != \#* ]]; then
                        UPSTREAM_REPO_LIST+=("$line")
                fi
        done <list.txt
else
        echo "no found repos"
        exit 1
fi

if [[ -n "${1:-}" ]]; then
        MIRROR_REPO_PREFIX="${1%/*}"
else
        echo "no set target repo"
        exit 1
fi

for UPSTREAM_REPO in "${UPSTREAM_REPO_LIST[@]}"; do
        MIRROR_REPO="${MIRROR_REPO_PREFIX}/$(basename "$UPSTREAM_REPO").git"

        rm -rf /tmp/upstream_mirror

        # 拉取上游仓库的更新
        echo "$UPSTREAM_REPO"
        git clone --mirror "$UPSTREAM_REPO" /tmp/upstream_mirror

        # 进入上游仓库的镜像目录
        pushd /tmp/upstream_mirror >/dev/null 2>&1 || exit

        # 将更新推送到镜像仓库
        git push --mirror "$MIRROR_REPO"
        echo "$MIRROR_REPO"

        # 返回原始目录并删除临时镜像目录
        popd >/dev/null 2>&1 || exit
        rm -rf /tmp/upstream_mirror
done

###
## 1: REPO=https://old.com/r/x mirror.sh https://new.com/backup
##    REPO="https://old.com/r/x,https://old.com/r/y" mirror.sh https://new.com/backup
## 2. mirror.sh git@new.com:backup https://old.com/r/x
## 3. mirror.sh git@new.com:backup
##    list.txt
##       https://old.com/r/x
##       https://old.com/r/y
###
