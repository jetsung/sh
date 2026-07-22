#!/usr/bin/env bash
#============================================================
# File: deb2rpm-docker.sh
# Description: 在 Docker 容器中将 deb 包转换为 rpm 包
# Author: Jetsung Chan <i@jetsung.com>
#============================================================

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <deb-file> <output-dir>"
    exit 1
fi

deb_file="$1"
output_dir="$2"

if [[ ! -f "$deb_file" ]]; then
    echo "Error: deb file not found: $deb_file"
    exit 1
fi

mkdir -p "$output_dir"

# 获取绝对路径
deb_abs_path="$(cd "$(dirname "$deb_file")" && pwd)/$(basename "$deb_file")"
output_abs_path="$(cd "$output_dir" && pwd)"

image_name="deb2rpm:latest"

# 镜像不存在时自动构建
if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    echo "Building Docker image: $image_name"
    docker build \
        -f "$(dirname "$0")/deb2rpm.Dockerfile" \
        -t "$image_name" \
        "$(dirname "$0")"
fi

echo "Converting $deb_abs_path -> $output_abs_path"

docker run --rm \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -v "$deb_abs_path:/input.deb:ro" \
    -v "$output_abs_path:/output" \
    "$image_name" \
    /input.deb /output
