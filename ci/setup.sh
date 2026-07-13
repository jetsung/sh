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
DOCS_ENABLED=0          # 是否显式传入了 --docs 开关
DOCS_DOMAIN=""          # --domain 的域名值（必须非空）
RELEASE_ENABLED=0       # 是否显式传入了 --release 开关

usage() {
    cat <<'EOF'
Usage: setup.sh -l <language> [-p <project>] [--docs] [--domain <domain>] [-h]

  -l, --language <lang>   目标语言（必填），如 rust
  -p, --project <value>   镜像归属，支持三种形态：
                           ORG/REPO  同时设置 image_org 与 package_name
                           myorg     仅设置 image_org
                           /myrepo   仅设置 package_name
      --docs              开关：下发 MkDocs 文档构建工作流（.github/workflows/docs.yml）
                           依赖通过 uv 在 docs.yml 中安装，无需 requirements.txt
      --domain <domain>   自定义域名（必填值），配合 --docs 在目标项目生成
                           docs/CNAME 文件写入该域名（GitHub Pages 自定义域名）
      --release           开关：下发语言原生二进制发布工作流（.github/workflows/<lang>-release.yml）
                           如 -l rust 则复制 rust/release.yml；配合 -p 的 REPO 名替换工作流内 APP 占位符
  -f, --force             强制覆盖已存在文件，跳过逐文件确认
  -h, --help              显示本帮助并退出

说明:
  compose.yaml 会随脚手架自动下发到项目 docker/ 目录（docker/compose.yaml）：脱敏
  模板，默认拉取预构建镜像，同时保留 build 段（docker compose up --build 可本地构建）。
  若目标已存在 docker/compose.yaml 则跳过（即使 -f）。配合 -p 的 REPO 名替换镜像与服务名占位符。

示例:
  curl -fsSL <base>/ci/setup.sh | bash -s -- -l rust
  bash setup.sh -l rust -p myorg/myrepo
  bash setup.sh -l rust --docs
  bash setup.sh -l rust --docs --domain example.com
  bash setup.sh -l rust --release -p myorg/myrepo
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
        --docs)
            DOCS_ENABLED=1
            shift
            ;;
        --release)
            RELEASE_ENABLED=1
            shift
            ;;
        --domain)
            DOCS_DOMAIN="${2:?"--domain requires a value"}"
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

# 2.7 将 docker/compose.yaml 内容内嵌到项目 README.md（移除 build 段，仅保留 ghcr 镜像方式）
compose_src="docker/compose.yaml"
if [[ -f "$compose_src" ]]; then
    {
        printf '\n'
        printf '#### docker/compose.yaml\n\n'
        printf '```yaml\n'
        # 去掉 build: 段（从 "    build:" 到下一个顶层键 "    ports:" 之前），仅保留 image 拉取方式
        awk '
            /^    build:/ { skip=1 }
            /^    ports:/ { skip=0 }
            !skip { print }
        ' "$compose_src"
        printf '```\n'
    } >> "$readme_dest"
    echo "已内嵌 $compose_src（移除 build 段）到 $readme_dest"
fi

if [[ -n "$PROJECT" && "$PROJECT" == */* ]]; then
    org="${PROJECT%%/*}"
    repo="${PROJECT##*/}"
    if [[ -n "$org" && -n "$repo" ]]; then
        replace_in_file "$readme_dest" 'ORG/REPO' "${org}/${repo}"
        echo "已替换 README.md 中的 ORG/REPO 为 ${org}/${repo}"
    fi
fi

#------------------------------------------------------------
# 文档工作流下发（--docs）
#------------------------------------------------------------

if [[ "$DOCS_ENABLED" -eq 1 ]]; then
    # 3.1 拉取工作流模板到临时文件
    docs_tmp="$(mktemp)"
    fetch_file "docs/docs.yml" "$docs_tmp"

    # 3.2 写入目标工作流（复用 maybe_write 的覆盖确认逻辑，内容来自已处理的临时文件）
    docs_dest=".github/workflows/docs.yml"
    answer="y"
    if [[ -f "$docs_dest" ]]; then
        answer="y"
        if [[ -t 0 && -t 1 && "$FORCE_OVERWRITE" != "1" && -z "${CI:-}" && -z "${FORCE:-}" ]]; then
            if read -r -t 30 -p "文件已存在: $docs_dest ，是否覆盖? [y/N] " answer; then
                answer="${answer:-n}"
            else
                answer="y"
            fi
        fi
        case "$answer" in
            y|Y|yes|YES) ;;
            *)
                echo "跳过: $docs_dest"
                answer="skip"
                ;;
        esac
    fi
    if [[ "$answer" != "skip" ]]; then
        mkdir -p "$(dirname "$docs_dest")"
        cp "$docs_tmp" "$docs_dest"
        echo "已写入: $docs_dest"
    fi
    rm -f "$docs_tmp"

    # 3.2.1 下发 mkdocs.yml 到项目根（docs.yml 工作流监听 mkdocs.yml 变更）
    # 若目标已存在（无论 -f 与否）则跳过，保留用户原有文件
    mkdocs_dest="mkdocs.yml"
    if [[ -f "$mkdocs_dest" ]]; then
        echo "已存在: $mkdocs_dest，已跳过下发（-f 不影响此文件）。"
    else
        maybe_write "$mkdocs_dest" "docs/mkdocs.yml"
    fi

    # 3.2.2 若提供了 -p，将 mkdocs.yml 中的 ORG/REPO 占位分别替换为组织与仓库名
    if [[ -n "$PROJECT" ]]; then
        mkdocs_org=""
        mkdocs_repo=""
        if [[ "$PROJECT" == /* ]]; then
            # 仅 REPO：形如 /myrepo，org 缺省为作者默认 org
            mkdocs_repo="${PROJECT#/}"
            mkdocs_org="jetsung"
        elif [[ "$PROJECT" == */* ]]; then
            # ORG/REPO：两半均非空
            mkdocs_org="${PROJECT%%/*}"
            mkdocs_repo="${PROJECT##*/}"
        else
            # 仅 ORG：形如 myorg，repo 未知，仅替换 org
            mkdocs_org="$PROJECT"
        fi
        if [[ -n "$mkdocs_org" ]]; then
            replace_in_file "$mkdocs_dest" 'ORG' "$mkdocs_org"
            echo "已替换 mkdocs.yml 中的 ORG 为 ${mkdocs_org}"
        fi
        if [[ -n "$mkdocs_repo" ]]; then
            replace_in_file "$mkdocs_dest" 'REPO' "$mkdocs_repo"
            echo "已替换 mkdocs.yml 中的 REPO 为 ${mkdocs_repo}"
        fi
    fi

    # 3.3 若提供了 --domain，在目标项目生成 docs/CNAME（GitHub Pages 自定义域名）
    if [[ -n "$DOCS_DOMAIN" ]]; then
        cname_dest="docs/CNAME"
        cname_answer="y"
        if [[ -f "$cname_dest" ]]; then
            cname_answer="y"
            if [[ -t 0 && -t 1 && "$FORCE_OVERWRITE" != "1" && -z "${CI:-}" && -z "${FORCE:-}" ]]; then
                if read -r -t 30 -p "文件已存在: $cname_dest ，是否覆盖? [y/N] " cname_answer; then
                    cname_answer="${cname_answer:-n}"
                else
                    cname_answer="y"
                fi
            fi
            case "$cname_answer" in
                y|Y|yes|YES) ;;
                *)
                    echo "跳过: $cname_dest"
                    cname_answer="skip"
                    ;;
            esac
        fi
        if [[ "$cname_answer" != "skip" ]]; then
            mkdir -p "$(dirname "$cname_dest")"
            printf '%s\n' "$DOCS_DOMAIN" > "$cname_dest"
            echo "已写入: $cname_dest (${DOCS_DOMAIN})"
        fi
    fi

    # 4.2 确保 MkDocs 构建产物 site/ 被 git 忽略
    # 不存在则创建；已存在但无 site/ 行则追加；已有则跳过，避免重复
    gitignore_dest=".gitignore"
    if [[ ! -f "$gitignore_dest" ]]; then
        printf '%s\n' "site/" > "$gitignore_dest"
        echo "已写入: $gitignore_dest (site/)"
    elif ! grep -q '^site/$' "$gitignore_dest"; then
        printf '%s\n' "site/" >> "$gitignore_dest"
        echo "已追加 site/ 到 $gitignore_dest"
    fi
fi

#------------------------------------------------------------
# 原生二进制发布工作流下发（--release）
#------------------------------------------------------------

if [[ "$RELEASE_ENABLED" -eq 1 ]]; then
    rel_src="${LANG_NAME}/release.yml"
    rel_dest=".github/workflows/release.yml"

    # 4.1 源不存在（该语言无发布工作流）则警告并跳过，不中断其余脚手架
    if ! curl -fsSL -o /dev/null "${BASE_URL%/}/${rel_src}"; then
        echo "警告: 语言 ${LANG_NAME} 暂无发布工作流（${rel_src}），已跳过 --release。" >&2
    else
        # 4.2 写入目标工作流（复用 maybe_write 的覆盖确认 / -f / CI 语义）
        maybe_write "$rel_dest" "$rel_src"
        echo "已下发发布工作流: $rel_dest"

        # 4.3 若 -p 解析出 REPO 名，将工作流内 APP 占位符替换为仓库名
        rel_repo=""
        case "$PROJECT" in
            /*)
                rel_repo="${PROJECT#/}"
                ;;
            */*)
                rel_repo="${PROJECT##*/}"
                ;;
        esac
        if [[ -n "$rel_repo" ]]; then
            replace_in_file "$rel_dest" 'APP' "$rel_repo"
            echo "已替换 ${rel_dest} 中的 APP 为 ${rel_repo}"
        fi
    fi
fi

#------------------------------------------------------------
# 多阶段 Dockerfile 合并
#------------------------------------------------------------

# 3.0 若目标 docker/Dockerfile 已存在，无论 -f 与否均跳过，保留用户原有文件
if [[ -f "docker/Dockerfile" ]]; then
    echo "已存在: docker/Dockerfile，已跳过合并生成（-f 不影响此文件）。"
else
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
fi

#------------------------------------------------------------
# compose.yaml 下发（脱敏模板，跳过已存在）
#------------------------------------------------------------

# 5.1 若目标 docker/compose.yaml 已存在（无论 -f 与否）则跳过，保留用户原有文件
if [[ -f "docker/compose.yaml" ]]; then
    echo "已存在: docker/compose.yaml，已跳过下发（-f 不影响此文件）。"
else
    maybe_write "docker/compose.yaml" "docker/compose.yaml"
    echo "已下发: docker/compose.yaml"

    # 5.2 若 -p 解析出 REPO 名，覆盖镜像与服务名占位符
    comp_repo=""
    comp_org="jetsung"
    case "$PROJECT" in
        /*)
            comp_repo="${PROJECT#/}"
            ;;
        */*)
            comp_org="${PROJECT%%/*}"
            comp_repo="${PROJECT##*/}"
            ;;
    esac
    if [[ -n "$comp_repo" ]]; then
        replace_in_file "docker/compose.yaml" '__APP_IMAGE__' "ghcr.io/${comp_org}/${comp_repo}"
        replace_in_file "docker/compose.yaml" '__APP_NAME__' "$comp_repo"
        replace_in_file "docker/compose.yaml" '__APP_CONTAINER__' "$comp_repo"
        replace_in_file "docker/compose.yaml" '__APP_HOST__' "$comp_repo"
        echo "已替换 docker/compose.yaml 中的占位符（org=${comp_org}, repo=${comp_repo}）"
    fi
fi

echo "完成：Docker CI 脚手架已下发（language=${LANG_NAME}${PROJECT:+, project=${PROJECT}}${DOCS_ENABLED:+, docs=enabled${DOCS_DOMAIN:+, domain=${DOCS_DOMAIN}}}）。"
