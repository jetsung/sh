#!/usr/bin/env bash

#============================================================
# File: gh-env.sh
# Description: 扫描 GitHub workflows 里引用的 secrets / vars，用 gh CLI 写入仓库配置
#   - 不依赖存放位置，按当前目录所属 git 仓库定位 .github/workflows
#   - 支持交互录入、--from-env 批量导入、镜像仓库凭据导入
# URL: 
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-10-29
# UpdatedAt: 2026-10-29
#============================================================

set -uo pipefail

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  echo "错误：需要 bash 4.3+" >&2
  exit 1
fi

KINDS=(vars secrets)

# GitHub 自动注入，无需用户配置
BUILTIN_RE='^(GITHUB_TOKEN|INSTANCE_ID)$'

DOCKER_CONFIG_FILE="${DOCKER_CONFIG:-$HOME/.docker}/config.json"

# 常见约定的说明表（由 describe 经 nameref 动态访问）；未登记的键会走通用文案
# shellcheck disable=SC2034
declare -A vars_table=(
  [PAGES_DOMAIN]="gh-pages 部署使用的自定义域名 CNAME，留空则不设独立域名"
  [ENABLE_SSH_DEPLOY]="是否启用 SSH 部署 job，取值 true / false"
)
# shellcheck disable=SC2034
declare -A secrets_table=(
  [SSH_HOSTNAME]="SSH 部署目标主机地址"
  [SSH_PORT]="SSH 端口，通常 22"
  [SSH_USERNAME]="SSH 登录用户名"
  [SSH_KEY]="SSH 私钥内容（整段，建议用 @/path/to/key 从文件读取）"
  [EDGEONE_API_TOKEN]="EdgeOne Pages 部署 API Token"
  [DOCKERHUB_USERNAME]="Docker Hub 用户名（与 TOKEN 成对配置后同步镜像才生效）"
  [DOCKERHUB_TOKEN]="Docker Hub 访问令牌（Access Token，非登录密码）"
)

usage() {
  cat <<EOF
用法: $(basename "$0") [选项] [NAME=VALUE ...]

模式:
  --list                        列出本项目需要哪些变量及用途
  --check                       对比已配置 / 缺失（缺失退出码 1，可用于 CI）
  --docker-sync                 只做镜像仓库凭据导入
  （无参数）                    交互式逐项录入（secret 隐藏输入），并比对镜像仓库渠道
  --from-env <文件>             从 .env 风格文件批量导入
  --repo <owner/name>           指定目标仓库（org/repo 均可）
  --workflows <目录>            指定 workflows 目录
  --docker-config <路径>        指定 docker config.json
  --no-docker                   关闭镜像仓库凭据环节
  --dry-run                     预演，不改动远端
  -y, --yes                     非交互，全部取默认值
  -h, --help                    显示本帮助

赋值:
  NAME=VALUE                    直接赋值（按 workflow 引用自动判定 vars / secrets）
  vars.NAME=VALUE               显式写入变量
  secrets.NAME=VALUE            显式写入 secret
  NAME=@<文件>                  @ 前缀表示从文件读取值（支持多行）

示例:
  $(basename "$0") PAGES_DOMAIN=docs.example.com
  $(basename "$0") secrets.FOO=bar vars.FOO=baz
  $(basename "$0") SSH_KEY=@~/.ssh/id_ed25519
  $(basename "$0") --from-env .env.gh --dry-run
  $(basename "$0") --repo owner/name --check

目标仓库识别顺序:
  --repo 指定 > git remote 里 github.com 的 owner/repo（多个时优先 origin，
  仍无法判定则列出候选让你选择）> gh 自动识别

镜像仓库凭据导入（依赖 jq）:
  以 docker-release.yml 为准：从各 sync-to-* job 里解析 registry 域名，
  与 ~/.docker/config.json 的 auths 对账。
  - 命中：解出账号/密码，确认后一键写入 <前缀>_USERNAME / <前缀>_TOKEN
  - 未命中：提示手动输入账号与密码/Token，再写入
  - 没有 docker-release.yml：跳过整个环节

安装:
  install -m 755 gh-env ~/.local/bin/      # 需保证 ~/.local/bin 在 PATH
  sudo install -m 755 gh-env /usr/local/bin/
  命名遵循 gh 扩展约定，安装后 gh-env 与 gh env 等价
EOF
}

# ---------- 工具函数 ----------

# 关联数组键：kind/name（变量名不含斜杠，故可安全用作分隔符）
skey() { # $1=kind $2=name
  printf '%s/%s' "$1" "$2"
}

describe() { # $1=kind $2=name
  local -n tbl="${1}_table"
  printf '%s' "${tbl[$2]:-未在说明表中登记，用途请参考 workflow 里的引用处}"
}

# 成组配置的键：写入其中一个时提示其余项
group_of() {
  case "$1" in
    SSH_*) echo "SSH_HOSTNAME SSH_PORT SSH_USERNAME SSH_KEY" ;;
    *_USERNAME) echo "${1%_USERNAME}_USERNAME ${1%_USERNAME}_TOKEN" ;;
    *_TOKEN) echo "${1%_TOKEN}_USERNAME ${1%_TOKEN}_TOKEN" ;;
    *) echo "" ;;
  esac
}

read_value() { # @ 前缀表示值来自文件内容（便于传入多行私钥）
  if [[ "$1" == @* ]]; then
    local file="${1:1}"
    [[ -r "$file" ]] || { echo "错误：无法读取文件 $file" >&2; return 1; }
    cat -- "$file"
  else
    printf '%s' "$1"
  fi
}

in_list() { # $1=空格分隔列表 $2=名称
  [[ " $1 " == *" $2 "* ]]
}

is_configured() { # $1=kind $2=name
  [[ -n "${HAVE[$1]}" && $'\n'"${HAVE[$1]}"$'\n' == *$'\n'"$2"$'\n'* ]]
}

confirm_yn() { # $1=提示 $2=默认(y/n) → 是返回 0
  local def="${2:-n}" ans=""
  if ((NON_INTERACTIVE)); then
    ans="$def"
    echo "$1 [$def]（非交互，取默认）" >&2
  elif ! read -r -p "$1 [$def]: " ans </dev/tty; then
    return 1
  fi
  ans="${ans,,}"
  [[ -z "$ans" ]] && ans="$def"
  case "$ans" in
    y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

collect() { # $1=kind → 输出 workflows 目录里被引用的名称（已排序去重）
  local regex
  case "$1" in
    secrets) regex='secrets\.[A-Za-z_][A-Za-z0-9_]*' ;;
    vars) regex='vars\.[A-Za-z_][A-Za-z0-9_]*' ;;
  esac
  grep -rhoE "$regex" "$WORKFLOW_DIR" --include='*.yml' --include='*.yaml' \
    | sed -E 's/.*\.//' | grep -Ev "$BUILTIN_RE" | sort -u
}

existing() { # $1=kind → 输出仓库已配置的名称
  local sub=variable
  [[ "$1" == secrets ]] && sub=secret
  local out
  if ! out=$(gh "$sub" list "${REPO_ARG[@]}" --json name -q '.[].name' 2>&1); then
    echo "错误：无法读取已有配置（$out）" >&2
    echo "请确认已执行 gh auth login 且仓库名正确。" >&2
    exit 1
  fi
  printf '%s\n' "$out" | grep -v '^$' || true
}

# git remote URL → owner/repo（支持 https://、ssh://、scp 简写、带 token 的 URL）
remote_repo() { # $1=url → 输出 owner/repo；非 github.com 或格式不符返回 1
  local url="$1" host path
  if [[ "$url" == *"://"* ]]; then
    host="${url#*://}"
    host="${host%%/*}"
    path="${url#*://}"
    path="${path#*/}"
  else
    host="${url%%:*}"
    path="${url#*:}"
  fi
  host="${host##*@}" # 去掉 user@ / token@
  host="${host%:*}"  # 去掉 ssh 端口
  path="${path%/}"
  path="${path%.git}"
  [[ "$host" == github.com || "$host" == www.github.com ]] || return 1
  [[ "$path" =~ ^[^/]+/[^/]+$ ]] || return 1
  printf '%s' "$path"
}

# 收集当前仓库所有指向 github.com 的 remote，输出一个 owner/repo
declare -a REPO_CANDIDATES=()
detect_repo_from_git() {
  local line name url repo origin=""
  REPO_CANDIDATES=()
  while IFS= read -r line; do
    name="${line%% *}"
    name="${name#remote.}"
    name="${name%.url}"
    url="${line#* }"
    repo="$(remote_repo "$url")" || continue
    in_list "${REPO_CANDIDATES[*]-}" "$repo" || REPO_CANDIDATES+=("$repo")
    [[ "$name" == origin ]] && origin="$repo"
  done < <(git config --get-regexp '^remote\..*\.url$' 2>/dev/null)

  case ${#REPO_CANDIDATES[@]} in
    0) return 1 ;;
    1)
      printf '%s' "${REPO_CANDIDATES[0]}"
      return 0
      ;;
  esac
  if [[ -n "$origin" ]]; then
    printf '%s' "$origin"
    return 0
  fi
  local i ans
  echo "检测到多个 GitHub remote：" >&2
  for i in "${!REPO_CANDIDATES[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${REPO_CANDIDATES[$i]}" >&2
  done
  ((NON_INTERACTIVE)) && return 1
  read -r -p "选择目标仓库编号（回车取消）: " ans </dev/tty || return 1
  [[ "$ans" =~ ^[0-9]+$ ]] || return 1
  ((ans < 1 || ans > ${#REPO_CANDIDATES[@]})) && return 1
  printf '%s' "${REPO_CANDIDATES[$((ans - 1))]}"
}

store() { # $1=kind $2=name $3=value
  if ((DRY_RUN)); then
    echo "  [dry-run] 将写入 $1 $2（${#3} 字符）"
    return 0
  fi
  local sub=variable
  [[ "$1" == secrets ]] && sub=secret
  # secret 走标准输入，避免值出现在进程列表里
  local ok=0
  if [[ "$1" == secrets ]]; then
    printf '%s' "$3" | gh "$sub" set "$2" "${REPO_ARG[@]}" && ok=1
  else
    gh "$sub" set "$2" --body "$3" "${REPO_ARG[@]}" && ok=1
  fi
  if ((ok)); then
    echo "  已写入 $1.$2"
  else
    echo "  写入失败 $2" >&2
    return 1
  fi
}

ask() { # $1=kind $2=name → 结果写入全局 ANSWER（空值表示跳过）
  ANSWER=""
  ((NON_INTERACTIVE)) && return 0
  # 说明与提示一律走 stderr，从 /dev/tty 取值，避免与命令替换/管道冲突
  echo >&2
  echo "$1.$2：$(describe "$1" "$2")" >&2
  local raw=""
  if [[ "$1" == secrets ]]; then
    read -r -s -p "  输入值（留空跳过，@文件可读取内容）: " raw </dev/tty
    echo >&2
  else
    read -r -p "  输入值（留空跳过，@文件可读取内容）: " raw </dev/tty
  fi
  ANSWER="$(read_value "$raw")"
}

# 解析 NAME=VALUE：允许 vars. / secrets. 前缀显式指定类型
resolve_kind() { # $1=key → 输出 kind（vars/secrets）
  local key="$1" name=""
  case "$key" in
    vars.*) printf 'vars'; return 0 ;;
    secrets.*) printf 'secrets'; return 0 ;;
  esac
  name="$key"
  if in_list "${NEEDED[vars]}" "$name"; then
    printf 'vars'
  elif in_list "${NEEDED[secrets]}" "$name"; then
    printf 'secrets'
  elif [[ -v vars_table[$name] ]]; then
    printf 'vars'
  elif [[ -v secrets_table[$name] ]]; then
    printf 'secrets'
  else
    # workflow 未引用且不在说明表：按更安全的 secret 处理
    printf 'secrets'
    echo "  提示：$name 未被 workflow 引用，默认写入 secret（如需明文请用 vars.$name=）" >&2
  fi
}

# ---------- 镜像仓库渠道对账 ----------

docker_release_file() {
  local f
  for f in "$WORKFLOW_DIR/docker-release.yml" "$WORKFLOW_DIR/docker-release.yaml"; do
    [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

# 同时引用了 <前缀>_USERNAME 与 <前缀>_TOKEN 的渠道前缀
channel_prefixes() {
  local file="$1"
  local users tokens
  users=$(grep -oE 'secrets\.[A-Z0-9]+_USERNAME' "$file" | sed -E 's/^secrets\.//; s/_USERNAME$//' | sort -u)
  tokens=$(grep -oE 'secrets\.[A-Z0-9]+_TOKEN' "$file" | sed -E 's/^secrets\.//; s/_TOKEN$//' | sort -u)
  comm -12 <(printf '%s\n' "$users") <(printf '%s\n' "$tokens")
}

# 在 sync-to-<渠道> job 块内查找 `registry: ${{ env.<KEY> }}`
registry_env_key() { # $1=file $2=job 名
  awk -v job="$2" '
    $0 ~ "^  " job ":[[:space:]]*$" { inside = 1; next }
    inside && /^  [A-Za-z0-9_-]+:/ { inside = 0 }
    inside && $0 ~ /registry:[[:space:]]*\$\{\{[[:space:]]*env\./ {
      sub(/.*env\./, ""); sub(/[^A-Za-z0-9_].*/, ""); print; exit
    }
  ' "$1"
}

# 顶层 env 块里某个键的值
env_value() { # $1=file $2=key
  awk -v k="$2" '
    /^env:/ { ine = 1; next }
    ine && /^[^[:space:]]/ { ine = 0 }
    ine && $0 ~ "^  " k ":" {
      sub(/^  [^:]+:[[:space:]]*/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print; exit
    }
  ' "$1"
}

registry_host_for() { # $1=file $2=前缀 → 域名，解析不出则输出空
  local file="$1" prefix="$2" key val
  key="$(registry_env_key "$file" "sync-to-$(tr '[:upper:]' '[:lower:]' <<<"$prefix")")"
  if [[ -n "$key" ]]; then
    val="$(env_value "$file" "$key")"
    if [[ -n "$val" ]]; then
      printf '%s' "$val"
      return 0
    fi
  fi
  [[ "$prefix" == DOCKERHUB ]] && printf 'docker.io'
}

# docker config.json 的 auths 键可能是 https://x/v1/ 形式，归一化成主机名
normalize_host() { # $1=原始键
  local s="$1"
  s="${s#https://}"
  s="${s#http://}"
  s="${s%%/*}"
  printf '%s' "$s"
}

# 从 docker config.json 取该域名的凭据 → "匹配键<TAB>用户名<TAB>密码"
# 仅精确匹配主机名：ccr 与 sgccr 属不同渠道，不会互相命中
config_lookup() { # $1=host
  [[ -r "$DOCKER_CONFIG_FILE" ]] || return 1
  command -v jq >/dev/null || { echo "  提示：未安装 jq，无法解析 $DOCKER_CONFIG_FILE" >&2; return 1; }
  local host="$1" b64="" key="" k v norm
  # 只按主机名精确匹配（去掉协议前缀与尾部路径段），不同渠道绝不互相命中
  while IFS=$(printf '\t') read -r k v; do
    [[ -z "$k" ]] && continue
    norm="$(normalize_host "$k")"
    if [[ "$norm" == "$host" || ("$norm" == index.docker.io && "$host" == docker.io) ]]; then
      key="$k"
      b64="$v"
      break
    fi
  done < <(jq -r '.auths // {} | to_entries[] | [.key, (.value.auth // "")] | @tsv' "$DOCKER_CONFIG_FILE" 2>/dev/null)
  [[ -z "$b64" ]] && return 1
  local decoded
  decoded=$(printf '%s' "$b64" | base64 -d 2>/dev/null) || return 1
  printf '%s\t%s\t%s' "$key" "${decoded%%:*}" "${decoded#*:}"
}

# 导入单个渠道：命中本地凭据则一键导入，否则走手动输入
docker_import_channel() { # $1=workflow 文件 $2=前缀
  local file="$1" p="$2"
  local u="${p}_USERNAME" t="${p}_TOKEN"
  # 显式传值时交给主流程逐项写入
  if [[ -n "${ASSIGN[$(skey secrets "$u")]-}" || -n "${ASSIGN[$(skey secrets "$t")]-}" ]]; then
    echo "  $p：已显式传值，跳过自动导入"
    return 0
  fi
  local host cred matched user pass un tk
  host="$(registry_host_for "$file" "$p")"
  if is_configured secrets "$u" && is_configured secrets "$t"; then
    echo
    echo "  $p（${host:-未声明 registry}）：GitHub 已配置 $u / $t"
    # 不覆盖时也认领这两个键，避免主流程重复报告
    if ! confirm_yn "    是否用本地凭据覆盖" n; then
      HANDLED[$(skey secrets "$u")]=1
      HANDLED[$(skey secrets "$t")]=1
      return 0
    fi
  fi

  cred=""
  [[ -n "$host" ]] && cred="$(config_lookup "$host")"

  if [[ -n "$cred" ]]; then
    IFS=$(printf '\t') read -r matched user pass <<<"$cred"
    echo
    echo "  $p：registry=$host，本地凭据来自 $matched"
    echo "    账号=$user 密码=****（共 ${#pass} 位）"
    if ! confirm_yn "    一键写入 $u / $t" y; then
      echo "    已取消导入 $p"
      return 0
    fi
  else
    echo
    echo "  $p：registry=${host:-workflow 未声明}，$DOCKER_CONFIG_FILE 无匹配凭据"
    if ! confirm_yn "    改为手动输入该渠道的账号与密码" n; then
      echo "    已跳过 $p"
      return 0
    fi
    un=""
    tk=""
    read -r -p "    账号（${host:-registry}）: " un </dev/tty || return 0
    read -r -s -p "    密码 / Access Token: " tk </dev/tty
    echo >&2
    if [[ -z "$un" || -z "$tk" ]]; then
      echo "    账号或密码为空，跳过 $p"
      return 0
    fi
    user="$un"
    pass="$tk"
  fi

  # 认领这两个键，避免主流程重复询问
  HANDLED[$(skey secrets "$u")]=1
  HANDLED[$(skey secrets "$t")]=1
  if store secrets "$u" "$user"; then
    ((docker_changed++))
  else
    ((docker_failed++))
  fi
  if store secrets "$t" "$pass"; then
    ((docker_changed++))
  else
    ((docker_failed++))
  fi
}

docker_import() {
  local file prefixes p
  if ! file="$(docker_release_file)"; then
    echo "未找到 docker-release.yml，跳过镜像仓库凭据导入。"
    return 0
  fi
  prefixes="$(channel_prefixes "$file")"
  if [[ -z "$prefixes" ]]; then
    echo "${file##*/} 未声明 *_USERNAME / *_TOKEN 渠道，跳过镜像仓库凭据导入。"
    return 0
  fi

  echo
  echo "镜像仓库渠道（${file##*/} ↔ $DOCKER_CONFIG_FILE）："
  [[ -r "$DOCKER_CONFIG_FILE" ]] || echo "  注意：本地无可读的 $DOCKER_CONFIG_FILE，全部渠道将走手动输入。"

  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    docker_import_channel "$file" "$p"
  done <<<"$prefixes"
}

# ---------- 参数解析 ----------

REPO=""
WORKFLOWS=""
DRY_RUN=0
NON_INTERACTIVE=0
MODE="set"
FROM_ENV=""
SKIP_DOCKER=0
declare -a RAW=()

while (($#)); do
  case "$1" in
    --repo) REPO="${2:?--repo 需要参数}"; shift 2 ;;
    --repo=*) REPO="${1#*=}"; shift ;;
    --workflows) WORKFLOWS="${2:?--workflows 需要参数}"; shift 2 ;;
    --workflows=*) WORKFLOWS="${1#*=}"; shift ;;
    --docker-config) DOCKER_CONFIG_FILE="${2:?--docker-config 需要参数}"; shift 2 ;;
    --docker-config=*) DOCKER_CONFIG_FILE="${1#*=}"; shift ;;
    --docker-sync) MODE="docker"; shift ;;
    --no-docker) SKIP_DOCKER=1; shift ;;
    --list) MODE="list"; shift ;;
    --check) MODE="check"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) NON_INTERACTIVE=1; shift ;;
    --from-env) FROM_ENV="${2:?--from-env 需要参数}"; shift 2 ;;
    --from-env=*) FROM_ENV="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while (($#)); do RAW+=("$1"); shift; done ;;
    *) RAW+=("$1"); shift ;;
  esac
done

for a in "${RAW[@]}"; do
  if [[ "$a" != *=* ]]; then
    echo "错误：位置参数必须写成 NAME=VALUE 形式（收到：$a）" >&2
    echo "提示：值里含 = 或特殊字符时用 --from-env 文件传入更稳妥" >&2
    exit 1
  fi
done

command -v gh >/dev/null || { echo "错误：未安装 gh CLI" >&2; exit 1; }

# 定位当前项目的 workflows 目录：显式指定 > git 根 > 当前目录
if [[ -z "$WORKFLOWS" ]]; then
  project_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "$project_root" ]] && project_root="$PWD"
  WORKFLOWS="$project_root/.github/workflows"
fi
WORKFLOW_DIR="$(cd "$WORKFLOWS" 2>/dev/null && pwd || true)"
if [[ -z "$WORKFLOW_DIR" ]]; then
  echo "错误：找不到 workflows 目录 $WORKFLOWS" >&2
  echo "请在目标仓库内运行，或用 --workflows <目录> / --repo owner/name 指定" >&2
  exit 1
fi

REPO_ARG=()
[[ -n "$REPO" ]] && REPO_ARG=(--repo "$REPO")

declare -A NEEDED=()
for kind in "${KINDS[@]}"; do
  NEEDED[$kind]="$(collect "$kind" | tr '\n' ' ')"
  NEEDED[$kind]="${NEEDED[$kind]## }"
done

if [[ "$MODE" == list ]]; then
  for kind in "${KINDS[@]}"; do
    read -ra names <<<"${NEEDED[$kind]}"
    echo
    echo "$kind（${#names[@]} 项）"
    for name in "${names[@]}"; do
      printf '  %s —— %s\n' "$name" "$(describe "$kind" "$name")"
    done
  done
  echo
  echo "来源：$WORKFLOW_DIR"
  exit 0
fi

if [[ -n "$REPO" ]]; then
  echo "目标仓库：$REPO（--repo 指定）"
elif detected_repo="$(detect_repo_from_git)"; then
  REPO="$detected_repo"
  REPO_ARG=(--repo "$REPO")
  echo "目标仓库：$REPO（git remote 匹配 github.com）"
elif gh_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" && [[ -n "$gh_repo" ]]; then
  REPO="$gh_repo"
  REPO_ARG=(--repo "$REPO")
  echo "目标仓库：$REPO（gh 自动识别）"
else
  echo "错误：未能识别目标仓库，请在 GitHub 仓库内运行或用 --repo owner/name 指定" >&2
  exit 1
fi

declare -A HAVE=()
for kind in "${KINDS[@]}"; do
  HAVE[$kind]="$(existing "$kind")"
done

if [[ "$MODE" == check ]]; then
  missing_total=0
  for kind in "${KINDS[@]}"; do
    read -ra names <<<"${NEEDED[$kind]}"
    declared=0
    echo
    echo "$kind（${#names[@]} 项）："
    for name in "${names[@]}"; do
      if is_configured "$kind" "$name"; then
        ((declared++))
      else
        ((missing_total++))
        printf '  缺失 %s —— %s\n' "$name" "$(describe "$kind" "$name")"
      fi
    done
    echo "  已配置 $declared / ${#names[@]}"
  done
  if docker_release_file >/dev/null; then
    echo
    echo "提示：镜像仓库渠道凭据可用 gh-env --docker-sync 从 $DOCKER_CONFIG_FILE 导入"
  fi
  exit $((missing_total > 0 ? 1 : 0))
fi

# 收集赋值：--from-env 先填，位置参数优先级更高
declare -A ASSIGN=() # key = kind/name → value
take_assignment() { # $1=key $2=raw value
  local kind name value
  kind="$(resolve_kind "$1")" || exit 1
  case "$1" in
    vars.*) name="${1#vars.}" ;;
    secrets.*) name="${1#secrets.}" ;;
    *) name="$1" ;;
  esac
  value="$(read_value "$2")" || exit 1
  ASSIGN[$(skey "$kind" "$name")]="$value"
}

if [[ -n "$FROM_ENV" ]]; then
  [[ -r "$FROM_ENV" ]] || { echo "错误：无法读取 $FROM_ENV" >&2; exit 1; }
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
    take_assignment "$key" "$val"
  done <"$FROM_ENV"
fi

for a in "${RAW[@]}"; do
  take_assignment "${a%%=*}" "${a#*=}"
done

changed=0
skipped=0
failed=0
docker_changed=0
docker_failed=0
declare -A HANDLED=() # 已处理的 kind/name

# 先做镜像仓库渠道对账，再逐项补齐其余变量
if [[ "$MODE" == docker ]]; then
  docker_import
  echo
  echo "完成：写入 $((docker_changed + changed)) 项，失败 $((docker_failed + failed)) 项。"
  exit $(((docker_failed + failed) > 0 ? 1 : 0))
fi
((SKIP_DOCKER)) || docker_import

for kind in "${KINDS[@]}"; do
  read -ra names <<<"${NEEDED[$kind]}"
  for name in "${names[@]}"; do
    key="$(skey "$kind" "$name")"
    [[ -v HANDLED[$key] ]] && continue
    HANDLED[$key]=1
    value="${ASSIGN[$key]-}"
    if [[ -z "$value" ]] && is_configured "$kind" "$name"; then
      echo
      echo "$kind.$name 已存在，跳过（传 $name=... 可覆盖）"
      ((skipped++))
      continue
    fi
    if [[ -z "$value" ]]; then
      ask "$kind" "$name"
      value="$ANSWER"
    fi
    if [[ -z "$value" ]]; then
      echo "  跳过 $name"
      ((skipped++))
      continue
    fi
    if store "$kind" "$name" "$value"; then
      ((changed++))
      group="$(group_of "$name")"
      if [[ -n "$group" ]]; then
        pending=()
        for sib in $group; do
          [[ "$sib" == "$name" ]] && continue
          in_list "${NEEDED[$kind]}" "$sib" || continue
          is_configured "$kind" "$sib" && continue
          [[ -n "${ASSIGN[$(skey "$kind" "$sib")]-}" ]] && continue
          [[ -v HANDLED[$(skey "$kind" "$sib")] ]] && continue
          pending+=("$sib")
        done
        ((${#pending[@]})) && echo "  提示：同组变量还需配置 ${pending[*]}"
      fi
    else
      ((failed++))
    fi
  done
done

# workflow 未引用但显式传入的键也要写入
for key in "${!ASSIGN[@]}"; do
  [[ -v HANDLED[$key] ]] && continue
  kind="${key%%/*}"
  name="${key#*/}"
  value="${ASSIGN[$key]}"
  if [[ -z "$value" ]]; then
    echo "  跳过 $name（未提供值）"
    ((skipped++))
    continue
  fi
  echo
  echo "$kind.$name：workflow 未引用，按显式指定写入"
  if store "$kind" "$name" "$value"; then
    ((changed++))
  else
    ((failed++))
  fi
done

echo
echo "完成：写入 $((docker_changed + changed)) 项，跳过 $skipped 项，失败 $((docker_failed + failed)) 项。"
exit $(((docker_failed + failed) > 0 ? 1 : 0))
