#!/usr/bin/env bash

#============================================================
# File: docker-copy.sh
# Description: Docker 镜像复制至新的注册表
# URL: https://s.fx4.cn/dockercopy
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

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认目标仓库映射
declare -A REGISTRY_MAP=(
    ["aliyun"]="registry.cn-guangzhou.aliyuncs.com"
    ["tencent"]="ccr.ccs.tencentyun.com"
    ["dockerhub"]="docker.io"
    ["huawei"]="swr.cn-south-1.myhuaweicloud.com"
    # 可以添加更多注册表映射
)

# 打印帮助信息
print_help() {
    echo -e "${BLUE}用法:${NC}"
    echo -e "  $0 --import SOURCE_IMAGE --output TARGET_REGISTRY [--targets TARGET1,TARGET2...]"
    echo -e ""
    echo -e "${BLUE}可用目标注册表:${NC}"
    for key in "${!REGISTRY_MAP[@]}"; do
        echo -e "  ${YELLOW}$key${NC} -> ${REGISTRY_MAP[$key]}"
    done
    echo -e ""
    echo -e "${BLUE}示例:${NC}"
    echo -e "  $0 --import docker://tencent/jetsung/minio:RELEASE.2025-04-22T22-12-26Z --output aliyun"
    echo -e "  $0 --import docker://tencent/jetsung/minio:RELEASE.2025-04-22T22-12-26Z --output all --targets aliyun,huawei"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--import)
            SOURCE_IMAGE="$2"
            shift 2
            ;;
        -o|--output)
            TARGET_REGISTRY="$2"
            shift 2
            ;;
        -t|--targets)
            IFS=',' read -ra TARGETS <<< "$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            print_help
            exit 1
            ;;
    esac
done

# 检查必要参数
if [[ -z "${SOURCE_IMAGE:-}" || -z "${TARGET_REGISTRY:-}" ]]; then
    echo -e "${RED}错误: 缺少必要参数${NC}"
    print_help
    exit 1
fi

# 提取源镜像的仓库和标签
if [[ "$SOURCE_IMAGE" =~ ^docker://([^/]+)/([^:]+)(:([^/]+))?$ ]]; then
    # SOURCE_REGISTRY=${BASH_REMATCH[1]}
    SOURCE_REPO=${BASH_REMATCH[2]}
    SOURCE_TAG=${BASH_REMATCH[4]:-latest}
else
    echo -e "${RED}错误: 无效的源镜像格式，请使用 docker://registry/repo:tag 格式${NC}"
    exit 1
fi

# 如果没有指定特定目标，则使用所有映射的目标
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    if [[ "$TARGET_REGISTRY" == "all" ]]; then
        TARGETS=("${!REGISTRY_MAP[@]}")
    else
        TARGETS=("$TARGET_REGISTRY")
    fi
fi

# 对每个目标执行复制操作
for target in "${TARGETS[@]}"; do
    if [[ -z "${REGISTRY_MAP[$target]}" ]]; then
        echo -e "${YELLOW}警告: 未知目标注册表: $target${NC}"
        continue
    fi
    
    TARGET_REGISTRY_URL="${REGISTRY_MAP[$target]}"
    TARGET_IMAGE="docker://${TARGET_REGISTRY_URL}/${SOURCE_REPO}:${SOURCE_TAG}"
    
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}正在复制镜像:${NC}"
    echo -e "源镜像: ${YELLOW}$SOURCE_IMAGE${NC}"
    echo -e "目标镜像: ${YELLOW}$TARGET_IMAGE${NC}"
    echo -e "${BLUE}========================================${NC}\n"
    
    # 执行skopeo复制
    if skopeo copy --all "$SOURCE_IMAGE" "$TARGET_IMAGE"; then
        echo -e "\n${GREEN}✅ 成功复制到 $target${NC}\n"
    else
        echo -e "\n${RED}❌ 复制到 $target 失败${NC}\n"
    fi
done

# 通用镜像复制脚本
# 用法: docker-copy.sh --import SOURCE_IMAGE --output TARGET_REGISTRY [--targets TARGET1,TARGET2...]