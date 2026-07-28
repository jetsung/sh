#!/usr/bin/env bash
#============================================================
# File: deb2rpm-docker.sh
# Description: 在 Docker 容器中将 deb 包转换为 rpm 包
# Author: Jetsung Chan <i@jetsung.com>
#============================================================

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <deb-file|url> <output-dir>"
    exit 1
fi

deb_file="$1"
output_dir="$2"

mkdir -p "$output_dir"

# 获取输出目录的绝对路径
output_abs_path="$(cd "$output_dir" && pwd)"

if [[ "$deb_file" == http://* || "$deb_file" == https://* ]]; then
    # URL 方式：直接透传给容器内的 deb2rpm.sh 处理下载
    echo "Download URL: $deb_file"
    container_deb="$deb_file"
    volume_opts=(-v "$output_abs_path:/output")
else
    # 本地文件方式：检查并挂载只读文件
    if [[ ! -f "$deb_file" ]]; then
        echo "Error: deb file not found: $deb_file"
        exit 1
    fi
    deb_abs_path="$(cd "$(dirname "$deb_file")" && pwd)/$(basename "$deb_file")"
    container_deb="/input.deb"
    volume_opts=(-v "$deb_abs_path:/input.deb:ro" -v "$output_abs_path:/output")
fi

image_name="${DEB2RPM_IMAGE:-ghcr.io/jetsung/deb2rpm}"

# 镜像不存在时提示用户先拉取
if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    echo "Error: image '$image_name' not found. Run: docker pull $image_name"
    exit 1
fi

echo "Converting $deb_file -> $output_abs_path"

docker run --rm \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    "${volume_opts[@]}" \
    "$image_name" \
    "$container_deb" /output
