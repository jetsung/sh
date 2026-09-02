#!/usr/bin/env bash
#
# add-installer-script: 为 install/ 目录生成新的工具安装脚本
#
# 用法: ./create-script.sh <REPO_OR_URL> [选项]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ============================================================
# 向上查找仓库的 install/ 目录
# ============================================================
find_install_dir() {
    local d="$SCRIPT_DIR"
    while [[ "$d" != "/" && -n "$d" ]]; do
        if [[ -d "$d/install" ]]; then
            echo "$d/install"
            return 0
        fi
        d="$(dirname "$d")"
    done
    echo "$PWD/install"
}

INSTALL_DIR="$(find_install_dir)"

# ============================================================
# 字面替换（避免 sed / ${var//} 对 & 与反斜杠的特殊处理）
# 用法: fill <PLACEHOLDER> <值>   （stdin -> stdout）
# ============================================================
fill() {
    local ph="$1" val="$2"
    P_VALUE="$val" awk -v ph="$ph" '
        BEGIN { rep = ENVIRON["P_VALUE"]; n = length(ph) }
        {
            line = $0
            out = ""
            while ((i = index(line, ph)) > 0) {
                out = out substr(line, 1, i - 1) rep
                line = substr(line, i + n)
            }
            print out line
        }'
}

# ============================================================
# 解析 GitHub 仓库：支持 URL / owner/repo
# ============================================================
parse_github_repo() {
    local input="$1"
    if [[ "$input" =~ ^https?://github\.com/([^/]+)/([^/?#]+) ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    elif [[ "$input" =~ ^([^/[:space:]]+)/([^/[:space:]]+)$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    else
        echo ""
    fi
}

# ============================================================
# 校验工具名（只允许安全字符，避免污染生成的脚本）
# ============================================================
validate_tool_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        error "工具名不合法: $name（只允许字母、数字、点、下划线、连字符）"
        exit 1
    fi
}

# ============================================================
# 从仓库名推断工具名
# ============================================================
get_tool_name_from_repo() {
    local repo="$1"
    echo "${repo##*/}" | tr '[:upper:]' '[:lower:]'
}

# ============================================================
# 从下载 URL 推断工具名
# ============================================================
infer_filename_from_url() {
    local url="$1"
    local base
    base=$(basename "${url%%\?*}" | tr '[:upper:]' '[:lower:]')
    base=$(echo "$base" | sed -E \
        -e 's/\.(tar\.(gz|xz|bz2|zst)|tgz|txz|zip|gz|xz|bz2|7z|deb|rpm|apk)$//' \
        -e 's/-v?[0-9][0-9.]*[0-9a-z-]*//g' \
        -e 's/_(v)?[0-9][0-9.]*[0-9a-z_]*//g' \
        -e 's/(amd64|x86_64|x64|arm64|aarch64|i686|linux|darwin|macos|windows|musl|gnu|apple|unknown|pc|freebsd|static|portable)//g' \
        -e 's/[-_.]+$//' \
        -e 's/^[-_.]+//')
    [[ -z "$base" ]] && base=""
    echo "$base"
}

# ============================================================
# 当前平台的匹配正则（与生成脚本内保持一致）
# 输出: OS_RE ARCH_RE
# ============================================================
get_platform_regex() {
    local os arch os_re arch_re
    os="$(uname | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    os_re="$os"
    case "$os" in
        darwin) os_re="darwin|macos|osx|apple" ;;
        linux)  os_re="linux" ;;
    esac

    arch_re="$arch"
    case "$arch" in
        x86_64|i686)      arch_re="x86_64|amd64|x64" ;;
        aarch64|arm64)    arch_re="aarch64|arm64|armv8" ;;
        armv7l)           arch_re="armv7|armhf" ;;
    esac

    echo "$os_re $arch_re"
}

# ============================================================
# 请求 GitHub releases API
# ============================================================
fetch_github_release() {
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null || echo ""
}

# ============================================================
# 获取 GitHub 仓库描述（供 AI 总结中文描述时参考）
# ============================================================
fetch_repo_description() {
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/${repo}" 2>/dev/null \
        | jq -r '.description // empty' 2>/dev/null || true
}

# ============================================================
# 从 release JSON 中挑选匹配当前平台的资产
# 输出: <下载URL>\t<文件名>；无匹配则输出空
# ============================================================
find_matching_asset() {
    local json="$1" os_re="$2" arch_re="$3"

    [[ -z "$json" ]] && { echo ""; return 0; }

    if ! command -v jq >/dev/null 2>&1; then
        error "需要 jq 才能解析 GitHub releases 资产列表"
        echo ""
        return 0
    fi

    local url
    # 1) OS + ARCH 同时匹配（排除校验文件）
    url=$(echo "$json" | jq -r --arg os "$os_re" --arg arch "$arch_re" '
        .assets[]?
        | select(.name | test("(?i)\\.(sha256|sha512|asc|sig|pem|json|txt|yaml|yml|deb|rpm|apk)$") | not)
        | select(.name | test($os; "i") and test($arch; "i"))
        | .browser_download_url
    ' 2>/dev/null | head -n 1)

    # 2) 仅匹配架构
    if [[ -z "$url" ]]; then
        url=$(echo "$json" | jq -r --arg arch "$arch_re" '
            .assets[]?
            | select(.name | test("(?i)\\.(sha256|sha512|asc|sig|pem|json|txt|yaml|yml|deb|rpm|apk)$") | not)
            | select(.name | test($arch; "i"))
            | .browser_download_url
        ' 2>/dev/null | head -n 1)
    fi

    if [[ -n "$url" && "$url" != "null" ]]; then
        printf '%s\t%s\n' "$url" "$(basename "$url")"
    else
        echo ""
    fi
}

# ============================================================
# 根据文件名推断下载类型
# ============================================================
detect_file_type() {
    local fname
    fname=$(basename "$1")
    case "$fname" in
        *.tar.gz|*.tgz)     echo "tar_gz" ;;
        *.tar.xz|*.txz)     echo "tar_xz" ;;
        *.tar.bz2)          echo "tar_bz2" ;;
        *.tar.zst|*.tar.zstd) echo "tar_zst" ;;
        *.tar)              echo "tar" ;;
        *.zip)              echo "zip" ;;
        *.gz)               echo "gz_binary" ;;
        *.xz)               echo "xz_binary" ;;
        *.bz2)              echo "bz2_binary" ;;
        *)                  echo "binary" ;;
    esac
}

# ============================================================
# 根据类型给出：下载文件名 + 展开命令（单行，不含 &）
# 展开结果：压缩包 -> extract/ 目录；压缩二进制 -> raw_bin
# ============================================================
prepare_command() {
    local file_type="$1"
    case "$file_type" in
        tar_gz)   echo "package.tar.gz" 'tar -xzf "$download_file" -C extract' ;;
        tar_xz)   echo "package.tar.xz" 'tar -xJf "$download_file" -C extract' ;;
        tar_bz2)  echo "package.tar.bz2" 'tar -xjf "$download_file" -C extract' ;;
        tar_zst)  echo "package.tar.zst" 'tar --zstd -xf "$download_file" -C extract' ;;
        tar)      echo "package.tar" 'tar -xf "$download_file" -C extract' ;;
        zip)      echo "package.zip" 'unzip -q "$download_file" -d extract' ;;
        gz_binary) echo "package.bin.gz" 'gunzip -c "$download_file" > raw_bin' ;;
        xz_binary) echo "package.bin.xz" 'xz -dc "$download_file" > raw_bin' ;;
        bz2_binary) echo "package.bin.bz2" 'bunzip2 -c "$download_file" > raw_bin' ;;
        *)        echo "raw_bin" ':' ;;
    esac
}

# ============================================================
# 生成脚本模板：主体（头部 + 通用函数 + download_exact）
# ============================================================
template_body() {
    cat <<'BODY_EOF'
#!/usr/bin/env bash

#============================================================
# File: @@FILE_NAME@@
# Description: @@DESC@@
# Source: @@SOURCE_LINE@@
# URL: @@URL_LINE@@
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: @@DATE@@
# UpdatedAt: @@DATE@@
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

CDN_URL="${CDN:-https://fastfile.asfd.cn/}"

USER_ID="$(id -u)"

sudo_exec() {
    if [[ "$USER_ID" -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

check_is_command() {
    command -v "$1" >/dev/null 2>&1
}

check_in_china() {
    if [[ -n "${CN:-}" ]]; then
        return 0 # 手动指定
    fi
    if [[ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" == "000" ]]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}

# 若为 https://xxx.xx 不以 / 结尾，则组合时去掉加速网址的 https://
#   格式为 https://file.xxx.io/github.com/
# 若为 https://xxx.xx/ 以 / 结尾，则组合时保留加速网址的 https://
#   格式为 https://xxx.xx/https://github.com/
check_remove_https() {
    if [[ -n "$1" && "${1: -1}" != "/" ]]; then
        echo 1
    fi
}

do_remove_https() {
    local url="$1"
    if [[ -n "$NO_HTTPS" ]]; then
        # shellcheck disable=SC2001
        echo "$url" | sed 's|https:/||2'
    else
        echo "$url"
    fi
}

########################## 以上为通用函数 #########################

# 从 GitHub releases 中按正则挑选安装包地址
get_download_url() {
    local repo="$1" os_re="$2" arch_re="$3"
    local repo_api_url
    repo_api_url=$(do_remove_https "${CDN_URL}https://api.github.com/repos/${repo}/releases/latest")
    curl -fsSL "$repo_api_url" | jq -r --arg os "$os_re" --arg arch "$arch_re" '
        .assets[]?
        | select(.name | test("(?i)\\.(sha256|sha512|asc|sig|pem|json|txt|yaml|yml|deb|rpm|apk)$") | not)
        | select(.name | test($os; "i") and test($arch; "i"))
        | .browser_download_url
    ' | head -n 1
}

download_exact() {
    local file_bin="@@FILE_BIN@@"
    local download_file="@@DOWNLOAD_FILE@@"
    TMP_DIR=$(mktemp -d /tmp/@@TMP_PREFIX@@.XXXXXX)

    # shellcheck disable=SC2329
    cleanup() {
        rm -rf -- "$TMP_DIR"
    }
    trap cleanup EXIT

    pushd "$TMP_DIR" >/dev/null

    local _download_url=""
    if [[ -n "${CUSTOM_URL:-}" ]]; then
        _download_url="$CUSTOM_URL"
    else
        _download_url=$(do_remove_https "${CDN_URL}${DOWNLOAD_URL}")
    fi
    echo "下载地址: $_download_url"

    if ! curl -fL --retry 3 -o "$download_file" "$_download_url"; then
        echo "Error: Failed to download $_download_url"
        popd >/dev/null
        exit 1
    fi

    mkdir -p extract

    if ! @@PREPARE@@; then
        echo "Error: Extraction failed"
        popd >/dev/null
        exit 1
    fi

    # 自动定位可执行文件：兼容「包内含顶层目录」与「包内直接是二进制」两种结构
    local _src=""
    if [[ -s raw_bin ]]; then
        _src="raw_bin"
    elif [[ -f "$file_bin" ]]; then
        _src="$file_bin"
    else
        _src=$(find extract -type f -name "$file_bin" 2>/dev/null | head -n 1)
    fi
    if [[ -z "$_src" ]]; then
        _src=$(find extract -type f -perm -u+x 2>/dev/null | head -n 1)
    fi
    if [[ -z "$_src" ]]; then
        echo "Error: 安装包中未找到可执行文件 ${file_bin}，包内文件列表如下："
        find extract -type f 2>/dev/null | head -n 40
        popd >/dev/null
        exit 1
    fi

    sudo_exec install -m 0755 "$_src" "/usr/local/bin/${file_bin}"

    popd >/dev/null
}
BODY_EOF
}

# ============================================================
# 生成脚本模板：main
# ============================================================
template_main() {
    cat <<'MAIN_EOF'

main() {
    # 解析命令行参数
    CUSTOM_URL=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                CUSTOM_URL="$2"
                shift 2
                ;;
            *)
                echo "Usage: $0 [--url <download_url>]"
                exit 1
                ;;
        esac
    done

    if [[ -z "$CUSTOM_URL" && -n "${URL:-}" ]]; then
        CUSTOM_URL="$URL"
    fi

    # 优先级：命令行参数 > 环境变量 > 默认流程
    DOWNLOAD_URL="${CUSTOM_URL:-}"

    if [[ -z "$DOWNLOAD_URL" ]]; then
        if ! check_in_china; then
            CDN_URL=""
        fi

        NO_HTTPS=$(check_remove_https "$CDN_URL")

@@RESOLVE@@
    else
        echo "使用指定下载地址: $DOWNLOAD_URL"
    fi

    download_exact

    echo ""

    if ! check_is_command "@@TOOL@@"; then
        echo "@@TOOL@@ has not been installed successfully."
        echo ""
        exit 1
    fi

    echo "@@TOOL@@ has been installed successfully!"
    echo ""
    @@TOOL@@ --help || true
    echo ""
    @@TOOL@@ --version || true
    echo ""
}

main "$@"
MAIN_EOF
}

# ============================================================
# main 中的地址解析片段：GitHub releases 模式
# ============================================================
resolve_block_repo() {
    local repo="$1"
    cat <<RESOLVE_EOF
        OS="\$(uname | tr '[:upper:]' '[:lower:]')"
        ARCH="\$(uname -m)"

        OS_RE="\$OS"
        case "\$OS" in
            darwin) OS_RE="darwin|macos|osx|apple" ;;
        esac

        ARCH_RE="\$ARCH"
        case "\$ARCH" in
            x86_64|i686)   ARCH_RE="x86_64|amd64|x64" ;;
            aarch64|arm64) ARCH_RE="aarch64|arm64|armv8" ;;
            armv7l)        ARCH_RE="armv7|armhf" ;;
        esac

        DOWNLOAD_URL="\$(get_download_url ${repo} "\$OS_RE" "\$ARCH_RE")"

        if [[ -z "\$DOWNLOAD_URL" || "\$DOWNLOAD_URL" == "null" ]]; then
            echo "Error: 未在 ${repo} 的最新 release 中找到匹配 \$OS-\$ARCH 的安装包"
            exit 1
        fi
RESOLVE_EOF
}

# ============================================================
# main 中的地址解析片段：固定 URL 模式
# ============================================================
resolve_block_url() {
    # 地址以占位符注入，经 fill 做字面替换，避开转义问题
    printf "        DOWNLOAD_URL='@@FIXED_URL@@'\n"
}

# ============================================================
# 显示帮助
# ============================================================
show_help() {
    cat <<'EOF'
用法: create-script.sh <INPUT> [选项]

<INPUT> 可以是：
  1. GitHub 仓库（https://github.com/owner/repo 或 owner/repo）
  2. 直接的下载地址

选项:
  --tool-name NAME     指定工具名 / 文件名（默认从输入推断）
  --bin-name NAME      指定安装后的可执行文件名（默认同工具名）
  --description DESC   指定工具描述
  --source URL         指定源代码 / 官网地址（默认从 GitHub 仓库推断 https://github.com/owner/repo）
  --url URL            直接指定下载地址（覆盖 GitHub 推断）
  -o, --output FILE    指定输出文件名（默认 <工具名>.sh）
  --install            生成后移动到 install/ 目录
  --detect-only        只探测下载地址与文件类型，不生成脚本
  --list-assets        列出仓库最新 release 的全部资产
  -h, --help           显示帮助

示例:
  ./create-script.sh rtk-ai/rtk
  ./create-script.sh rtk-ai/rtk --detect-only
  ./create-script.sh rtk-ai/rtk --description "Rust 代码工具包" --install
  ./create-script.sh https://example.com/dl/tool.tar.xz --tool-name tool
EOF
}

# ============================================================
# 主流程
# ============================================================
main() {
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi

    local input="$1"
    shift

    local tool_name="" bin_name="" description="" custom_source="" custom_url="" output_file=""
    local do_install=false detect_only=false list_assets=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool-name)   tool_name="$2"; shift 2 ;;
            --bin-name)    bin_name="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --source)      custom_source="$2"; shift 2 ;;
            --url)         custom_url="$2"; shift 2 ;;
            -o|--output)   output_file="$2"; shift 2 ;;
            --install)     do_install=true; shift ;;
            --detect-only) detect_only=true; shift ;;
            --list-assets) list_assets=true; shift ;;
            -h|--help)     show_help; exit 0 ;;
            *)             error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    local repo=""
    if [[ "$input" =~ github\.com/ || "$input" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] && [[ ! "$input" =~ \.(tar|tgz|zip|gz|xz|bz2|zst) ]]; then
        repo="$(parse_github_repo "$input")"
    fi

    local platform=($(get_platform_regex))
    local os_re="${platform[0]}" arch_re="${platform[1]}"

    local download_url="" fname="" file_type="binary"

    if [[ -n "$custom_url" ]]; then
        download_url="$custom_url"
    elif [[ -n "$repo" ]]; then
        info "请求 GitHub API: ${repo}"
        local json
        json="$(fetch_github_release "$repo")"
        if [[ -z "$json" ]]; then
            error "无法获取 GitHub release 信息（仓库不存在或触发了 API 限流）"
            exit 1
        fi

        if [[ "$list_assets" == true ]]; then
            info "$repo 最新 release 资产:"
            echo "$json" | jq -r '.assets[]? | "  \(.name)\t\(.browser_download_url)"'
            exit 0
        fi

        local matched
        matched="$(find_matching_asset "$json" "$os_re" "$arch_re")"
        if [[ -z "$matched" ]]; then
            error "未找到匹配当前平台（${os_re} / ${arch_re}）的资产，可用资产如下："
            echo "$json" | jq -r '.assets[]? | "  \(.name)"'
            exit 1
        fi
        download_url="${matched%%$'\t'*}"
        fname="${matched#*$'\t'}"
    elif [[ "$input" =~ ^https?:// ]]; then
        download_url="$input"
    else
        error "无法识别的输入: $input"
        show_help
        exit 1
    fi

    fname="${fname:-$(basename "${download_url%%\?*}")}"
    file_type="$(detect_file_type "$fname")"

    # 准备下载文件名与展开命令
    local prep_line download_file prepare_cmd
    prep_line="$(prepare_command "$file_type")"
    download_file="${prep_line%% *}"
    prepare_cmd="${prep_line#* }"
    if [[ "$file_type" == "binary" ]]; then
        download_file="raw_bin"
        prepare_cmd=":"
    fi

    # 推断工具名
    if [[ -z "$tool_name" ]]; then
        if [[ -n "$repo" ]]; then
            tool_name="$(get_tool_name_from_repo "$repo")"
        else
            tool_name="$(infer_filename_from_url "$download_url")"
        fi
    fi
    if [[ -z "$tool_name" ]]; then
        error "无法推断工具名，请使用 --tool-name 指定"
        exit 1
    fi
    validate_tool_name "$tool_name"

    bin_name="${bin_name:-$tool_name}"
    validate_tool_name "$bin_name"

    # 探测阶段即获取仓库描述原文，供 AI 总结中文描述时参考
    local repo_desc=""
    if [[ -n "$repo" ]]; then
        repo_desc="$(fetch_repo_description "$repo")"
        # 清洗：合并换行、去尾随空白
        repo_desc="$(printf '%s' "$repo_desc" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
    fi

    info "工具名:   $tool_name"
    info "可执行名: $bin_name"
    info "资产文件: $fname"
    info "下载地址: $download_url"
    info "文件类型: $file_type"
    [[ -n "$repo_desc" ]] && info "仓库描述: $repo_desc（供 AI 总结中文用）"

    if [[ "$detect_only" == true ]]; then
        exit 0
    fi

    # 描述：--description 优先；未指定时提醒用 AI 总结一句中文（不自动写入英文原文）
    if [[ -z "$description" ]]; then
        if [[ -n "$repo_desc" ]]; then
            warn "未指定 --description：请用 AI 根据以上仓库描述总结一句中文，再以 --description 传入"
        else
            warn "未指定 --description：头部 Description 将留空"
        fi
    fi
    [[ -z "$description" ]] && description=""

    # 头部 Source：--source 优先；GitHub 仓库默认推断为源码地址；直接下载地址则留空
    local source_line=""
    if [[ -n "$custom_source" ]]; then
        source_line="$custom_source"
    elif [[ -n "$repo" ]]; then
        source_line="https://github.com/${repo}"
    fi

    # 头部 URL 默认留空（不自动写入仓库地址或下载地址）
    local url_line=""

    output_file="${output_file:-${tool_name}.sh}"

    local date_now
    date_now="$(date '+%Y-%m-%d')"

    local resolve
    if [[ -n "$repo" ]]; then
        resolve="$(resolve_block_repo "$repo")"
    else
        # 单引号会破坏生成的脚本，直接拒绝
        if [[ "$download_url" == *"'"* ]]; then
            error "下载地址包含单引号，无法安全生成脚本"
            exit 1
        fi
        resolve="$(resolve_block_url)"
    fi

    # 渲染模板
    {
        template_body | fill "@@FILE_NAME@@" "$output_file" \
            | fill "@@DESC@@" "$description" \
            | fill "@@SOURCE_LINE@@" "$source_line" \
            | fill "@@URL_LINE@@" "$url_line" \
            | fill "@@DATE@@" "$date_now" \
            | fill "@@FILE_BIN@@" "$bin_name" \
            | fill "@@DOWNLOAD_FILE@@" "$download_file" \
            | fill "@@TMP_PREFIX@@" "$tool_name" \
            | fill "@@PREPARE@@" "$prepare_cmd"
        template_main | fill "@@RESOLVE@@" "$resolve" \
            | fill "@@FIXED_URL@@" "$download_url" \
            | fill "@@TOOL@@" "$tool_name"
    } > "$output_file"

    chmod +x "$output_file"

    if ! bash -n "$output_file"; then
        error "生成的脚本语法有误: $output_file"
        exit 1
    fi
    info "脚本已生成: $output_file（语法校验通过）"

    if [[ "$do_install" == true ]]; then
        if [[ ! -d "$INSTALL_DIR" ]]; then
            error "找不到 install 目录: $INSTALL_DIR"
            exit 1
        fi
        local target="${INSTALL_DIR}/${output_file}"
        if [[ -e "$target" ]]; then
            error "文件已存在: $target（请先确认后再覆盖）"
            exit 1
        fi
        mv "$output_file" "$target"
        info "已放入: $target"

        # 不擅自更新 list.txt / README.md，两者由仓库维护者自行维护
        warn "不会自动更新 list.txt 与 README.md，如需登记请手动补充"
    else
        warn "下一步: bash -n ${output_file} && DEBUG=1 bash ${output_file}"
    fi
}

main "$@"