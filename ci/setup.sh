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
DOCS_ENABLED=""         # 是否显式传入了 --docs / -o 开关
DOCS_DOMAIN=""          # --domain / -D 的域名值（必须非空）
RELEASE_ENABLED=""      # 是否显式传入了 --release / -r 开关
RELEASE_LINUX_ENABLED=""  # 是否显式传入了 --release-linux / -L 开关（仅 Linux x86_64 预发布）
README_ENABLED=""       # 是否显式传入了 --readme / -e 开关（默认不下发/更新 README.md）
DOCKER_ENABLED=""       # 是否下发 docker 资源（默认不下发；--docker 显式启用）

usage() {
    cat <<'EOF'
Usage: setup.sh -l <language> [-a <project>] [-o] [-D <domain>] [-r] [-L] [-e] [-R] [-f] [-h]

  -l, --language <lang>   目标语言（必填），如 rust
  -a, --project <value>   镜像归属，支持三种形态：
                           ORG/REPO  同时设置 image_org 与 package_name
                           myorg     仅设置 image_org
                           /myrepo   仅设置 package_name
  -o, --docs              开关：下发 MkDocs 文档构建工作流（.github/workflows/docs.yml）
                           依赖通过 uv 在 docs.yml 中安装，无需 requirements.txt
  -D, --domain <domain>   自定义域名（必填值），配合 --docs 在目标项目生成
                           docs/CNAME 文件写入该域名（GitHub Pages 自定义域名）
  -r, --release           开关：下发语言原生二进制发布工作流（.github/workflows/<lang>-release.yml）
                           如 -l rust 则复制 rust/release.yml；配合 -a 的 REPO 名替换工作流内 APP 占位符
  -L, --release-linux     开关：额外下发 Linux x86_64 单平台单架构预发布工作流
                           （.github/workflows/<lang>-release-linux-prerelease.yml），仅响应
                           v*-preview* / v*-rc* / v*-alpha* / v*-beta* 标签，自动标记为 prerelease。
                           与 --release 相互独立，同时指定时两个工作流并存。
  -e, --readme            开关：下发并更新项目根 README.md（复制 docker/README.md 并内嵌
                           docker/compose.yaml）。默认不触碰 README.md，需显式启用才生成/更新。
                           依赖 -R/--docker：须同时启用 --docker 才有 compose.yaml 可内嵌。
  -R, --docker            开关：下发 docker 资源（docker/* 目录、.github/workflows/docker-*.yml、
                           Dockerfile 合并、docker/compose.yaml 下发及 README 内嵌）。
                           默认不下发；需要容器化的项目显式加 --docker 一并下发。
  -f, --force             强制覆盖已存在文件，跳过逐文件确认
  -h, --help              显示本帮助并退出

说明:
  compose.yaml 仅当 --docker 启用时下发到项目 docker/ 目录（docker/compose.yaml）：脱敏
  模板，默认拉取预构建镜像，同时保留 build 段（docker compose up --build 可本地构建）。
  若目标已存在 docker/compose.yaml 则跳过（即使 -f）。配合 -a 的 REPO 名替换镜像与服务名占位符。

示例:
  curl -fsSL <base>/ci/setup.sh | bash -s -- -l rust
  bash setup.sh -l rust -a myorg/myrepo
  bash setup.sh -l rust --docs
  bash setup.sh -l rust --docs --domain example.com
  bash setup.sh -l rust --release -a myorg/myrepo          # 纯 CLI，不发 docker/*
  bash setup.sh -l rust -R -e --release -a myorg/myrepo   # 全量：含 docker、README、release
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
        -a|--project)
            PROJECT="${2:?"--project requires a value"}"
            shift 2
            ;;
        -o|--docs)
            DOCS_ENABLED=1
            shift
            ;;
        -r|--release)
            RELEASE_ENABLED=1
            shift
            ;;
        -L|--release-linux)
            RELEASE_LINUX_ENABLED=1
            shift
            ;;
        -e|--readme)
            README_ENABLED=1
            shift
            ;;
        -R|--docker)
            DOCKER_ENABLED=1
            shift
            ;;
        -D|--domain)
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

# rust_cargo_check：检查当前目录 Cargo.toml 的 [package.metadata.deb] 与
# [package.metadata.generate-rpm] 段，缺失则补齐（用项目名替换 relaydrop），
# 已存在则提示跳过。仅当 Cargo.toml 存在时执行。
rust_cargo_check() {
    local cargo_file="Cargo.toml"
    if [[ ! -f "$cargo_file" ]]; then
        return 0
    fi

    # 项目名称：依次尝试 Cargo.toml 的 package.name、-p 的 REPO、relaydrop
    local pkg_name=""
    pkg_name="$(grep -m1 '^\s*name\s*=' "$cargo_file" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
    if [[ -z "$pkg_name" ]]; then
        case "${PROJECT:-}" in
            /*)    pkg_name="${PROJECT#/}" ;;
            */*)  pkg_name="${PROJECT##*/}" ;;
            *)     pkg_name="${PROJECT:-relaydrop}" ;;
        esac
    fi

    # 回显头：无论是否存在，先输出建议内容（项目名称已替换）
    echo "--- Cargo.toml 建议补全段（package=${pkg_name}）---"
    if ! grep -q '^\s*\[\s*package\.metadata\.deb\s*\]' "$cargo_file"; then
        cat <<DEB

[package.metadata.deb]
maintainer = "Jetsung Chan <i@jetsung.com>"
assets = [
    ["target/release/${pkg_name}", "usr/bin/${pkg_name}", "755"],
]
DEB
    fi
    if ! grep -q '^\s*\[\s*package\.metadata\.generate-rpm\s*\]' "$cargo_file"; then
        cat <<RPM

[package.metadata.generate-rpm]
maintainer = "Jetsung Chan <i@jetsung.com>"
assets = [
    { source = "target/release/${pkg_name}", dest = "/usr/bin/${pkg_name}", mode = "755" },
]
RPM
    fi
    echo "--- 建议结束 ---"

    # 1) [package.metadata.deb]
    if grep -q '^\s*\[\s*package\.metadata\.deb\s*\]' "$cargo_file"; then
        echo "[package.metadata.deb] 已存在，跳过。"
    else
        # 末尾有换行则直追加，否则先补换行
        if [[ -s "$cargo_file" ]] && [[ "$(tail -c1 "$cargo_file" | wc -l)" -eq 0 ]]; then
            printf '\n' >> "$cargo_file"
        fi
        cat >> "$cargo_file" <<DEB

[package.metadata.deb]
maintainer = "Jetsung Chan <i@jetsung.com>"
assets = [
    ["target/release/${pkg_name}", "usr/bin/${pkg_name}", "755"],
]
DEB
        echo "已追加 [package.metadata.deb] 到 ${cargo_file}。"
    fi

    # 2) [package.metadata.generate-rpm]
    if grep -q '^\s*\[\s*package\.metadata\.generate-rpm\s*\]' "$cargo_file"; then
        echo "[package.metadata.generate-rpm] 已存在，跳过。"
    else
        if [[ -s "$cargo_file" ]] && [[ "$(tail -c1 "$cargo_file" | wc -l)" -eq 0 ]]; then
            printf '\n' >> "$cargo_file"
        fi
        cat >> "$cargo_file" <<RPM

[package.metadata.generate-rpm]
maintainer = "Jetsung Chan <i@jetsung.com>"
assets = [
    { source = "target/release/${pkg_name}", dest = "/usr/bin/${pkg_name}", mode = "755" },
]
RPM
        echo "已追加 [package.metadata.generate-rpm] 到 ${cargo_file}。"
    fi
}

#------------------------------------------------------------
# 目录准备与文件下载
#------------------------------------------------------------

# 工作流 与 bake/dockerignore/Dockerfile 合并/compose.yaml 下发：
# 全部属于「docker 资源」，由 -R/--docker 控制（默认不下发）。
# 未启用 --docker 时整段跳过，仅保留工作流（--release）与文档（--docs）等。
if [[ "$DOCKER_ENABLED" -eq 1 ]]; then
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
                _app="${repo}"
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
else
    echo "已跳过 docker 资源（未启用 --docker）。"
fi

# 2.6 复制 docker/README.md 到项目根 README.md（仅 --readme 启用时）
# 默认不触碰 README.md；启用时才复制/追加，并将 readme_dest 设为有效值供段 5.3/5.4 使用。
readme_dest=""
if [[ "$README_ENABLED" -eq 1 ]]; then
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
fi

# 注意：docker/compose.yaml 内嵌到 README.md 的逻辑已移至本脚本末尾的「compose.yaml 下发」段之后，
# 确保占位符（__APP_*__）已完成 -p 替换后再内嵌，README 与落地文件保持一致。

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

# 4.0 --release 与 --release-linux 相互独立，各自下发对应文件到不同目标名
# 避免互相覆盖；同时指定 -r -L 时两个工作流并存于 .github/workflows/
if [[ -n "$RELEASE_ENABLED" ]]; then
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

        # 4.4 仅 rust：检查并补全 Cargo.toml 的 deb/rpm 元数据段
        if [[ "$LANG_NAME" == "rust" ]]; then
            rust_cargo_check
        fi
    fi
fi

if [[ -n "$RELEASE_LINUX_ENABLED" ]]; then
    rel_src="${LANG_NAME}/release-linux-prerelease.yml"
    rel_dest=".github/workflows/release-linux-prerelease.yml"

    # 4.5 源不存在（该语言无 linux 发布工作流）则警告并跳过，不中断其余脚手架
    if ! curl -fsSL -o /dev/null "${BASE_URL%/}/${rel_src}"; then
        echo "警告: 语言 ${LANG_NAME} 暂无 Linux 发布工作流（${rel_src}），已跳过 --release-linux。" >&2
    else
        # 4.6 写入目标工作流
        maybe_write "$rel_dest" "$rel_src"
        echo "已下发 Linux 发布工作流: $rel_dest"

        # 4.7 若 -p 解析出 REPO 名，将工作流内 APP 占位符替换为仓库名
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

        # 4.8 仅 rust：检查并补全 Cargo.toml 的 deb/rpm 元数据段
        if [[ "$LANG_NAME" == "rust" ]]; then
            rust_cargo_check
        fi
    fi
fi

#------------------------------------------------------------
# 多阶段 Dockerfile 合并（docker 资源，受 -R/--docker 控制）
#------------------------------------------------------------

# 3.0 若目标 docker/Dockerfile 已存在，无论 -f 与否均跳过，保留用户原有文件
if [[ "$DOCKER_ENABLED" -eq 1 ]]; then
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
fi

#------------------------------------------------------------
# compose.yaml 下发（脱敏模板，跳过已存在；受 -R/--docker 控制）
#------------------------------------------------------------

# 5.1 若目标 docker/compose.yaml 已存在（无论 -f 与否）则跳过，保留用户原有文件
if [[ "$DOCKER_ENABLED" -eq 1 ]]; then
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
fi

# 5.3 将 docker/compose.yaml 内容内嵌到项目 README.md
# 必须在 5.1/5.2 占位符替换之后执行，保证内嵌的是替换后的最终内容（而非 __APP_*__ 模板）。
# 无论本次是否新下发（目标已存在则跳过下发），只要 docker/compose.yaml 存在即内嵌其当前内容。
# 内嵌时移除 build: 段，仅保留 image 拉取（ghcr pull）方式。
# 依赖 docker 资源：未启用 --docker 时 compose.yaml 不存在，自然跳过。
compose_src="docker/compose.yaml"
if [[ -f "$compose_src" && -n "${readme_dest:-}" ]]; then
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

# 5.4 若 -p 含 ORG/REPO，将 README.md 追加内容中的 ORG/REPO 占位替换为组织与仓库名
# 仅当 README 已下发（readme_dest 非空，即启用 --readme）时才执行
if [[ -n "${readme_dest:-}" && -n "$PROJECT" && "$PROJECT" == */* ]]; then
    org="${PROJECT%%/*}"
    repo="${PROJECT##*/}"
    if [[ -n "$org" && -n "$repo" ]]; then
        replace_in_file "$readme_dest" 'ORG/REPO' "${org}/${repo}"
        echo "已替换 README.md 中的 ORG/REPO 为 ${org}/${repo}"
    fi
fi

echo "完成：CI 脚手架已下发（language=${LANG_NAME}${PROJECT:+, project=${PROJECT}}${DOCKER_ENABLED:+, docker=enabled}${DOCS_ENABLED:+, docs=enabled${DOCS_DOMAIN:+, domain=${DOCS_DOMAIN}}}${README_ENABLED:+, readme=enabled}${RELEASE_LINUX_ENABLED:+, release=enabled (linux)}${RELEASE_ENABLED:+, release=enabled}）。"
