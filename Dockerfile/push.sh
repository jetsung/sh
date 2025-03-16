#!/usr/bin/env bash

# 推送到 Registry

set -euo pipefail

# 列出所有本地镜像
docker_images=$(docker images --format "{{.Repository}}:{{.Tag}}")

# 列出所有已登录的 Registry
registries=$(jq -r '.auths | to_entries[] | .key' ~/.docker/config.json)
echo -e "\nregistry list: \n$registries\n\n"
if [[ -z "${registries:-}" ]]; then
    echo "No registries found in ~/.docker/config.json"
    exit 0
fi

# 遍历每个镜像
for image in $docker_images; do
    echo ""
    echo "image: $image"
    echo ""
    # 检查是否是 Docker Hub 的镜像
    if [[ $image == "library/"* || $image == *"/"* ]]; then
        # 获取镜像名称和标签
        repo=${image%:*}
        tag=${image##*:}
        # 如果没有标签，默认为 latest
        if [[ "$tag" = "$image" ]]; then
            tag="latest"
        fi

        # 遍历每个已登录的 Registry
        for registry in ${registries:-}; do
            # echo "registry: $registry"
            # 如果是 Docker Hub，则跳过
            if [[ $registry = *"docker.io"* ]]; then
                if ! docker push "$image" > /dev/null 2>&1; then
                    echo "Push failed for $image"
                else
                    echo "Push successful for $image"
                fi            
                continue
            fi

            # 打上新标签
            new_image="$registry/${repo#:library/}:${tag}"
            docker tag "$image" "$new_image"
            # 推送到新 Registry
            if ! docker push "$new_image" > /dev/null 2>&1; then
                echo "Push failed for $new_image"
            else
                echo "Push successful for $new_image"
            fi
        done
    fi
done  