#!/usr/bin/env bash

#============================================================
# File: setup.sh
# Description: 一键下发 Docker CI 脚手架到目标项目
# URL: https://git.asfd.cn/jetsung/sh/raw/branch/main/ci/setup.sh
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-07-11
# UpdatedAt: 2026-07-12
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 默认资源根：ci 仓库根；源文件路径相对此根并带 docker/ 前缀
BASE_URL="${BASE_URL:-https://git.asfd.cn/jetsung/sh/raw/branch/main/ci/}"

LANG_NAME=""
PROJECT=""
FORCE_OVERWRITE=0

usage() {
    cat <<'EOF'
Usage: setup.sh -l <language> [-p <project>] [-h]

  -l, --language <lang>   目标语言（必填），如 rust
  -p, --project <value>   镜像归属，支持三种形态：
                           ORG/REPO  同时设置 image_org 与 package_name
                           myorg     仅设置 image_org
                           /myrepo   仅设置 package_name
  -f, --force             强制覆盖已存在文件，跳过逐文件确认
  -h, --help              显示本帮助并退出

示例:
  curl -fsSL <base>/ci/setup.sh | bash -s -- -l rust
  bash setup.sh -l rust -p myorg/myrepo
EOF
}

#------------------------------------------------------------
# 参数解析
#------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--language)
            LANG_NAME="${2:?"--language requires a value"}"
            shift 2
            ;;
        -p|--project)
            PROJECT="${2:?"--project requires a value"}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -f|--force)
            FORCE_OVERWRITE=1
            shift
            ;;
        *)
            echo "未知参数: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$LANG_NAME" ]]; then
    echo "错误: 必须指定 --language (-l) 参数" >&2
    usage >&2
    exit 1
fi

#------------------------------------------------------------
# 辅助函数
#------------------------------------------------------------

# fetch_file <src_rel_path> <dest_path>
# 从 BASE_URL 拉取源文件到目标路径（已确保目标目录存在）
fetch_file() {
    local src_rel="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL -o "$dest" "${BASE_URL%/}/${src_rel}"
}

# maybe_write <fetch_or_content_fn> ...
# 若目标已存在，提示是否覆盖；用户拒绝则跳过并 continue 后续流程。
# 用法: maybe_write <dest> <src_rel_path_for_fetch>
maybe_write() {
    local dest="$1"
    local src_rel="$2"

    if [[ -f "$dest" ]]; then
        local answer="y"
        # 交互式终端且未强制（FORCE_OVERWRITE / FORCE / CI 均未触发）：询问用户
        if [[ -t 0 && -t 1 && "$FORCE_OVERWRITE" != "1" && -z "${CI:-}" && -z "${FORCE:-}" ]]; then
            if read -r -t 30 -p "文件已存在: $dest ，是否覆盖? [y/N] " answer; then
                answer="${answer:-n}"
            else
                answer="y"
            fi
        fi
        case "$answer" in
            y|Y|yes|YES) ;;
            *)
                echo "跳过: $dest"
                return 0
                ;;
        esac
    fi

    fetch_file "$src_rel" "$dest"
    echo "已写入: $dest"
}

# 替换文本文件中所有匹配项，原地修改
# replace_in_file <file> <search> <replace>
replace_in_file() {
    local file="$1" search="$2" replace="$3"
    [[ -f "$file" ]] || return 0
    # 兼容 BSD/GNU sed：使用不同分隔符避免 / 冲突
    search="${search//\//\\/}"
    replace="${replace//\//\\/}"
    replace="${replace//&/\\&}"
    sed -i.bak -e "s/${search}/${replace}/g" "$file"
    rm -f "${file}.bak"
}

#------------------------------------------------------------
# 目录准备与文件下载
#------------------------------------------------------------

# 工作流
maybe_write ".github/workflows/docker-dev.yml" "docker/docker-dev.yml"
maybe_write ".github/workflows/docker-release.yml" "docker/docker-release.yml"

# bake 与 dockerignore
maybe_write "docker/docker-bake.hcl" "docker/docker-bake.hcl"
maybe_write ".dockerignore" "docker/.dockerignore"

# 2.4 对需要源码触发的语言，向 dev 工作流的 on.push.paths 追加 "src/**"
# 仅 rust 等从 src/ 构建的语言需要；直接在 paths: 下一行插入
case "$LANG_NAME" in
    rust|go|python|node)
        dev_wf=".github/workflows/docker-dev.yml"
        if [[ -f "$dev_wf" ]] && ! grep -q 'src/\*\*' "$dev_wf"; then
            tmp_wf="$(mktemp)"
            inserted=0
            while IFS= read -r line; do
                printf '%s\n' "$line" >> "$tmp_wf"
                if [[ "$inserted" -eq 0 && "$line" == *"paths:"* ]]; then
                    printf '      - "src/**"\n' >> "$tmp_wf"
                    inserted=1
                fi
            done < "$dev_wf"
            mv "$tmp_wf" "$dev_wf"
            echo "已追加 src/** 到 $dev_wf"
        fi
        ;;
esac

# 2.5 根据 -p 形态写入 docker-release.yml 的 env.image_org / env.package_name
    if [[ -n "$PROJECT" ]]; then
        rel_wf=".github/workflows/docker-release.yml"
        if [[ -f "$rel_wf" ]]; then
            if [[ "$PROJECT" == /* ]]; then
                # 仅 REPO：形如 /myrepo
                repo="${PROJECT#/}"
                [[ -n "$repo" ]] && replace_in_file "$rel_wf" 'package_name:.*' "package_name: '${repo}'"
            elif [[ "$PROJECT" == */* ]]; then
                # ORG/REPO：两半均非空
                org="${PROJECT%%/*}"
                repo="${PROJECT##*/}"
                if [[ -n "$org" && -n "$repo" ]]; then
                    replace_in_file "$rel_wf" 'image_org:.*' "image_org: '${org}'"
                    replace_in_file "$rel_wf" 'package_name:.*' "package_name: '${repo}'"
                fi
            else
                # 仅 ORG：形如 myorg
                replace_in_file "$rel_wf" 'image_org:.*' "image_org: '${PROJECT}'"
            fi
            echo "已应用 -p ${PROJECT} 到 ${rel_wf}"
        fi
    fi

# 2.6 复制 docker/README.md 到项目根 README.md
# 已存在则追加（保留原内容），不存在则直接写入
readme_dest="README.md"
readme_tmp="$(mktemp)"
fetch_file "docker/README.md" "$readme_tmp"
if [[ -f "$readme_dest" ]]; then
    # 追加前加空行分隔原内容与新增内容
    printf '\n' >> "$readme_dest"
    cat "$readme_tmp" >> "$readme_dest"
    echo "已追加: $readme_dest"
else
    mv "$readme_tmp" "$readme_dest"
    echo "已写入: $readme_dest"
fi
rm -f "$readme_tmp"

if [[ -n "$PROJECT" && "$PROJECT" == */* ]]; then
    org="${PROJECT%%/*}"
    repo="${PROJECT##*/}"
    if [[ -n "$org" && -n "$repo" ]]; then
        replace_in_file "$readme_dest" 'ORG/REPO' "${org}/${repo}"
        echo "已替换 README.md 中的 ORG/REPO 为 ${org}/${repo}"
    fi
fi

#------------------------------------------------------------
# 多阶段 Dockerfile 合并
#------------------------------------------------------------

build_stage="$(mktemp)"
runtime_stage="$(mktemp)"
trap 'rm -f "$build_stage" "$runtime_stage"' EXIT

# 3.1 编译层: <lang>.<n>.Dockerfile
fetch_file "docker/${LANG_NAME}.1.Dockerfile" "$build_stage"

# 3.2 运行时层: cc-debian13.Dockerfile
fetch_file "docker/cc-debian13.Dockerfile" "$runtime_stage"

# 3.3 合并：编译层在前，runtime 在后
mkdir -p docker
cat "$build_stage" > docker/Dockerfile
echo "" >> docker/Dockerfile
cat "$runtime_stage" >> docker/Dockerfile
echo "已生成: docker/Dockerfile"

# 3.4 对 rust 且 -p 含有 REPO 的语言，将 Dockerfile 中 myapp 替换为项目名称
if [[ "$LANG_NAME" == "rust" && -n "$PROJECT" ]]; then
    repo=""
    case "$PROJECT" in
        /*)
            repo="${PROJECT#/}"
            ;;
        */*)
            repo="${PROJECT##*/}"
            ;;
    esac
    if [[ -n "$repo" ]]; then
        replace_in_file "docker/Dockerfile" 'myapp' "$repo"
        echo "已替换 Dockerfile 中的 myapp 为 ${repo}"
    fi
fi

echo "完成：Docker CI 脚手架已下发（language=${LANG_NAME}${PROJECT:+, project=${PROJECT}}）。"
