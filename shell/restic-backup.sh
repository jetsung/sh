#!/usr/bin/env bash
#============================================================
# File: restic-backup.sh
# Description: Restic 备份工具 - 支持本地/远程多仓库备份、自动触发（登录/关机/cron）、快照管理
# URL: https://fx4.cn/resticbackup
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.7.0
# UpdatedAt: 2026-09-07
#============================================================

# cron/systemd 环境的 PATH 不含 /usr/local/bin（restic 所在目录），显式补全
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if [[ -n "${DEBUG:-}" ]]; then
  set -eux
else
  set -euo pipefail
fi

SCRIPT_PATH="$(realpath "$0")"
CONFIG_DIR="$HOME/.config/restic-backup"
REPOS_FILE="$CONFIG_DIR/repos.txt"
SOURCES_FILE="$CONFIG_DIR/sources.txt"
ENV_FILE="$HOME/.config/environment.d/99-my-env.conf"
PASSWORD_FILE="$CONFIG_DIR/password"

# 从文件读取密码
if [[ -f "$PASSWORD_FILE" ]]; then
  export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"
else
  echo "WARNING: Password file not found at $PASSWORD_FILE"
fi

# local 仓库：检查本地文件夹是否存在
LOCAL_REPO="${RESTIC_REPOSITORY:-$HOME/databackup}"
LOCAL_REPO_EXISTS=false
LOCAL_REPO_URL=""
if [[ -d "$LOCAL_REPO" ]]; then
  LOCAL_REPO_EXISTS=true
  LOCAL_REPO_URL="local:$LOCAL_REPO"
fi

# 远程仓库列表
REMOTE_REPOS=()
if [[ -f "$REPOS_FILE" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && REMOTE_REPOS+=("$line")
  done < "$REPOS_FILE"
fi

# 启动时一次性依赖检查：restic 必装；存在远程仓库时 rclone 必装
# 且 repos.txt 中的渠道必须已在 rclone 中配置（登录），否则直接报错退出
check_dependencies() {
  local missing=()
  command -v restic >/dev/null 2>&1 || missing+=(restic)
  if (( ${#REMOTE_REPOS[@]} > 0 )); then
    command -v rclone >/dev/null 2>&1 || missing+=(rclone)
  fi
  if (( ${#missing[@]} > 0 )); then
    echo "ERROR: Missing required commands: ${missing[*]} (PATH=$PATH)"
    exit 1
  fi

  if (( ${#REMOTE_REPOS[@]} > 0 )); then
    local configured remote repo not_logged_in=()
    configured="$(rclone listremotes 2>/dev/null || true)"
    for repo in "${REMOTE_REPOS[@]}"; do
      [[ "$repo" == rclone:* ]] || continue
      remote="${repo#rclone:}"
      remote="${remote%%:*}"
      if ! grep -qix -- "${remote}:" <<< "$configured"; then
        not_logged_in+=("$remote")
      fi
    done
    if (( ${#not_logged_in[@]} > 0 )); then
      echo "ERROR: rclone remote(s) not configured (not logged in): ${not_logged_in[*]}"
      echo "Run 'rclone config' to add them, or fix $REPOS_FILE"
      exit 1
    fi
  fi
}
check_dependencies

# 从 sources.txt 读取备份目标（每行一个，# 开头为注释行，支持 $HOME 展开）
BACKUP_SOURCES=()
if [[ -f "$SOURCES_FILE" ]]; then
  while IFS= read -r line; do
    # 跳过空行与 # 开头的注释行
    [[ -z "$line" || "$line" == \#* ]] && continue
    BACKUP_SOURCES+=("$(eval echo "$line")")
  done < "$SOURCES_FILE"
fi

# 动态添加所有 Claude 相关的 settings 配置文件
# for f in $HOME/.config/claude/settings.*.json; do
#   [ -e "$f" ] && BACKUP_SOURCES+=("$f")
# done

# 仅桌面环境支持登录备份：graphical-session.target 依赖图形会话，无桌面的主机（VPS/服务器）不得安装
require_desktop() {
  if [[ -n "${XDG_CURRENT_DESKTOP:-}" || -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] \
    || systemctl --user is-active graphical-session.target >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: Login backup requires a desktop Linux environment (no graphical session detected)."
  echo "On headless servers (VPS), use --cron for scheduled backups."
  return 1
}

# 安装登录触发服务 (用户级)
install_login() {
  # 登录服务面向桌面环境的普通用户，root 无图形会话，不得安装
  if [[ "$EUID" -eq 0 ]]; then
    echo "ERROR: Login backup must be installed as a normal user (not root)."
    echo "Intended for desktop environments; on VPS/servers use --cron."
    return 1
  fi
  require_desktop || return 1
  local service_dir="$HOME/.config/systemd/user"
  mkdir -p "$service_dir"

  local env_line=""
  if [[ -f "$ENV_FILE" ]]; then
    env_line="EnvironmentFile=$ENV_FILE"
  fi

  cat > "$service_dir/restic-backup-login.service" <<EOF
[Unit]
Description=Restic Backup on Login

[Service]
Type=oneshot
$env_line
ExecStart=$SCRIPT_PATH

[Install]
WantedBy=graphical-session.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable restic-backup-login.service
  echo "Login service installed and enabled."
}

# 卸载登录触发服务（--install-login 的逆向操作）
uninstall_login() {
  if ! [[ -f "$HOME/.config/systemd/user/restic-backup-login.service" ]]; then
    echo "Login service not installed, nothing to do."
    return 0
  fi
  systemctl --user disable restic-backup-login.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/restic-backup-login.service"
  systemctl --user daemon-reload
  echo "Login service uninstalled."
}

# 卸载所有触发服务
uninstall_all() {
  uninstall_login

  # 历史遗留：清理旧版本的关机备份服务（如存在）
  sudo systemctl disable restic-backup-shutdown.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/restic-backup-shutdown.service
  [[ -f /etc/systemd/system/restic-backup-shutdown.service ]] && sudo systemctl daemon-reload

  # cron 任务：仅移除带管理标记的条目，避免误删用户自定义行
  crontab -l 2>/dev/null | grep -v "# restic-backup-managed" | crontab - 2>/dev/null || true

  echo "All services uninstalled."
}

# 校验 cron 时间字段（支持数字、*、步进 */n、范围 a-b、列表 a,b）
validate_cron_fields() {
  local fields=("$@")
  local maxs=(59 23 31 12 7)
  local names=("minute" "hour" "day" "month" "weekday")
  local i part num
  for ((i = 0; i < ${#fields[@]}; i++)); do
    IFS=',' read -ra parts <<< "${fields[i]}"
    for part in "${parts[@]}"; do
      if [[ "$part" == \** ]]; then
        [[ "$part" =~ ^\*(_/[0-9]+)?$ ]] || { echo "ERROR: Invalid cron field '${fields[i]}' (${names[i]})"; return 1; }
        continue
      fi
      if [[ "$part" =~ ^([0-9]+)(-([0-9]+))?(/[0-9]+)?$ ]]; then
        num="${BASH_REMATCH[1]}"
        (( num <= maxs[i] )) || { echo "ERROR: ${names[i]} value $num out of range (0-${maxs[i]})"; return 1; }
        if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
          (( BASH_REMATCH[3] <= maxs[i] )) || { echo "ERROR: ${names[i]} value ${BASH_REMATCH[3]} out of range (0-${maxs[i]})"; return 1; }
        fi
      else
        echo "ERROR: Invalid cron field '$part' (${names[i]})"
        return 1
      fi
    done
  done
  return 0
}

# 安装 cron 定时任务（无参数：凌晨随机时间；或 --cron <字段...> 指定时间，1-5 个字段，缺省补 *）
install_cron() {
  # 幂等：安装前先移除本脚本的旧条目（含不同安装路径的历史残留）
  local base
  base="$(basename "$SCRIPT_PATH")"
  crontab -l 2>/dev/null | grep -v "$base" | crontab - 2>/dev/null || true

  local min hour state_file="$CONFIG_DIR/cron.time"

  if [[ $# -eq 0 ]]; then
    # 每台机器固定一个随机时间（写回状态文件，重装不漂移）
    mkdir -p "$CONFIG_DIR"
    if [[ -f "$state_file" ]]; then
      read -r min hour <<< "$(cat "$state_file")"
    else
      min=$((RANDOM % 60))
      hour=$((RANDOM % 6))   # 0-5 点
      echo "$min $hour" > "$state_file"
    fi
    set -- "$min" "$hour"
  fi

  # 时间字段：分 时 日 月 周（1-5 个，不足 5 个用 * 补全）
  if (( $# > 5 )); then
    echo "Usage: $(basename "$0") --cron [分 [时 [日 [月 [周]]]]]"
    echo "ERROR: Too many time fields (max 5: minute hour day month weekday)."
    return 1
  fi
  local fields=("$@")
  validate_cron_fields "${fields[@]}" || return 1
  while (( ${#fields[@]} < 5 )); do
    fields+=("*")
  done

  # cron 默认 PATH 只有 /usr/bin:/bin，需补上 restic 所在的 /usr/local/bin 及脚本所在目录
  local script_dir
  script_dir="$(dirname "$SCRIPT_PATH")"
  local cron_line="${fields[*]} PATH=/usr/local/bin:/usr/bin:/bin:$script_dir restic-backup.sh >> /var/log/restic-backup.log 2>&1"

  # 追加时给条目打上管理标记，便于 uninstall 精确移除
  (crontab -l 2>/dev/null; echo "$cron_line # restic-backup-managed") | crontab -

  echo "Cron job installed: $cron_line"
}

# 显示帮助
show_help() {
  cat <<EOF
用法: $(basename "$0") [选项]

选项:
  -h, -?, --help        显示此帮助信息
  -i, --init [目标]     初始化指定的备份仓库
  -s, --show [目标]     查看快照
  -p, --prune [目标]    清理旧快照（保留最近3个 + 每月1日tag）
  -I, --install         安装自动备份服务：登录备份（仅桌面版 Linux，VPS 自动跳过）+ cron 定时任务
  -L, --install-login   仅安装登录时自动备份服务（仅桌面版 Linux）
  -c, --cron [分 时 日 月 周]  添加 cron 定时任务（无参数：凌晨随机时间；1-5 个字段，缺省补 *，如 --cron 30 3）
  -U, --uninstall-login 卸载登录时自动备份服务（--install-login 的逆向）
  -u, --uninstall       卸载所有自动备份服务（登录服务 + cron 任务）

备份行为:
  所有可用仓库（本地 + 远程）均执行备份，快照独立
  备份时默认排除所有 .git 文件夹

配置文件:
  $REPOS_FILE      远程仓库列表（每行一个）
  $SOURCES_FILE    备份目标列表（每行一个，# 开头为注释，空行忽略，支持 \$HOME）
  $PASSWORD_FILE   restic 仓库密码

Tag 规则:
  每月 1 日备份自动添加 tag: monthly-YYYYMM

保留策略:
  --prune 保留最近 3 个快照 + 所有带 monthly-* tag 的快照
  (自动 --retry-lock 处理陈旧锁，单个仓库失败不影响其它仓库)

仓库目标 [目标] 优先级:
  1. local                -> 本地仓库
  2. 文件路径(支持 ~)      -> 从该文件的逐行内容读取仓库列表
  3. 单一仓库地址          -> 指定仓库，如 rclone:qcloud:restic-<bucket-id>/<hostname>
  4. 不传参数              -> 全部仓库(本地 + 远程)

示例:
  $(basename "$0")                               # 执行备份
  $(basename "$0") --show                        # 查看所有快照
  $(basename "$0") --show local                  # 查看本地仓库快照
  $(basename "$0") --prune                       # 清理所有仓库
  $(basename "$0") --prune local                 # 仅清理本地仓库
  $(basename "$0") --prune ~/.config/restic-backup/repos.txt  # 按文件列表清理
  $(basename "$0") --prune rclone:qcloud:restic-<bucket-id>/<hostname>  # 清理指定仓库
  $(basename "$0") --init                        # 初始化所有仓库
  $(basename "$0") -h                        # 查看帮助

新增远程仓库:
  1. 在 $REPOS_FILE 中添加一行
  2. 运行 '$(basename "$0") --init' 初始化新仓库
  3. 之后正常备份即可

定义的仓库:
  本地: ${LOCAL_REPO_URL:-不存在 ($LOCAL_REPO)}
  远程: ${REMOTE_REPOS[*]:-无}
EOF
}

# 解析仓库目标。优先级:
#   1) "local"            -> 本地仓库
#   2) 指定为文件路径      -> 从文件读取仓库列表(逐行)
#   3) 指定为单一仓库地址  -> 该仓库
#   4) 不传参数            -> 所有仓库(本地 + 远程)
# 结果写入全局数组 RESOLVED_REPOS
resolve_repos() {
  RESOLVED_REPOS=()
  local target="${1:-}"

  if [[ -z "$target" ]]; then
    # 全部仓库
    [[ "$LOCAL_REPO_EXISTS" == "true" ]] && RESOLVED_REPOS+=("$LOCAL_REPO_URL")
    RESOLVED_REPOS+=("${REMOTE_REPOS[@]}")
    return
  fi

  # 1) 本地简写
  if [[ "$target" == "local" ]]; then
    if [[ "$LOCAL_REPO_EXISTS" != "true" ]]; then
      echo "ERROR: Local repository does not exist ($LOCAL_REPO)"
      return 1
    fi
    RESOLVED_REPOS=("$LOCAL_REPO_URL")
    return
  fi

  # 展开 ~ 后判断是否为文件
  local expanded="$target"
  [[ "$target" == "~"* ]] && expanded="$HOME${target:1}"
  if [[ -f "$expanded" ]]; then
    if [[ ! -r "$expanded" ]]; then
      echo "ERROR: Cannot read repository list file: $expanded"
      return 1
    fi
    while IFS= read -r line; do
      [[ -n "$line" ]] && RESOLVED_REPOS+=("$line")
    done < "$expanded"
    return
  fi

  # 3) 单一仓库地址
  RESOLVED_REPOS=("$target")
}

# 初始化仓库
init_repos() {
  if ! resolve_repos "${1:-}"; then
    exit 1
  fi
  local all_repos=("${RESOLVED_REPOS[@]}")

  if [[ ${#all_repos[@]} -eq 0 ]]; then
    echo "ERROR: No repositories available"
    exit 1
  fi

  for repo in "${all_repos[@]}"; do
    echo "------------------------------------------------"
    echo "Checking repository: $repo"
    if restic -r "$repo" snapshots >/dev/null 2>&1; then
      echo "Already initialized."
    else
      echo "Initializing repository..."
      restic -r "$repo" init
    fi
  done
}

# 预处理
clean_configs() {
  if [[ -f "$HOME/.codex/config.toml" ]]; then
    sed -i '/\[projects\.".*"\]/{N;/trust_level = "trusted"/d}' "$HOME/.codex/config.toml"
  fi
  if [[ -f "$HOME/.claude/settings.json" ]]; then
    sed -i '/"model": ".*"/d' "$HOME/.claude/settings.json"
  fi
}

# 清理旧快照
prune_snapshots() {
  if ! resolve_repos "${1:-}"; then
    exit 1
  fi
  local all_repos=("${RESOLVED_REPOS[@]}")

  if [[ ${#all_repos[@]} -eq 0 ]]; then
    echo "ERROR: No repositories available"
    exit 1
  fi

  local failed=0
  for repo in "${all_repos[@]}"; do
    echo "------------------------------------------------"
    echo "Pruning repository: $repo"

    # 单个仓库失败不中断其它仓库
    if ! restic -r "$repo" snapshots >/dev/null 2>&1; then
      echo "ERROR: Repository not initialized. Run '$(basename "$0") --init' first."
      restic -r "$repo" snapshots 2>&1 | tail -5
      failed=1
      continue
    fi

    echo "Keeping: last 3 snapshots + all monthly-* tagged snapshots"
    if ! restic -r "$repo" forget --retry-lock 10s \
              --group-by '' --keep-last 3 --keep-tag "monthly-*" --prune; then
      echo "ERROR: Prune failed for repository: $repo"
      failed=1
    fi
  done

  # 任一仓库失败则以非零码退出
  [[ "$failed" -eq 0 ]] || return 1
}

# 查看快照
show_snapshots() {
  local target_repos=()
  if [[ $# -gt 0 && -n "$1" ]]; then
    # 支持简写 "local" -> 完整本地仓库地址
    if [[ "$1" == "local" && "$LOCAL_REPO_EXISTS" == "true" ]]; then
      target_repos=("$LOCAL_REPO_URL")
    else
      target_repos=("$1")
    fi
  else
    [[ "$LOCAL_REPO_EXISTS" == "true" ]] && target_repos+=("$LOCAL_REPO_URL")
    [[ ${#REMOTE_REPOS[@]} -gt 0 ]] && target_repos+=("${REMOTE_REPOS[@]}")
  fi

  if [[ ${#target_repos[@]} -eq 0 ]]; then
    echo "ERROR: No repositories available"
    exit 1
  fi

  for repo in "${target_repos[@]}"; do
    echo "------------------------------------------------"
    echo "Repository: $repo"
    restic -r "$repo" snapshots -c
  done
}

# 参数解析
case "${1:-}" in
-h | -\? | --help)
  show_help
  exit 0
  ;;
-i | --init)
  init_repos "${2:-}"
  exit 0
  ;;
-s | --show)
  show_snapshots "${2:-}"
  exit 0
  ;;
-c | --cron)
  install_cron "${@:2}"
  exit 0
  ;;
-p | --prune)
  prune_snapshots "${2:-}"
  exit 0
  ;;
-I | --install | -L | --install-login | -U | --uninstall-login | -u | --uninstall)
  case "${1:-}" in
  -I | --install)
    # 与 --uninstall 对称：登录备份 + cron 一起装
    # 非桌面环境（VPS）登录备份不可用，跳过后继续安装 cron
    install_login || true
    install_cron
    ;;
  -L | --install-login)
    install_login
    ;;
  -U | --uninstall-login)
    uninstall_login
    ;;
  -u | --uninstall)
    uninstall_all
    ;;
  esac
  exit 0
  ;;
-*|\?*)
  echo "ERROR: Unknown option: $1"
  show_help
  exit 1
  ;;
esac

# 主备份流程
echo "Running pre-backup cleanup..."
clean_configs

# 构建备份参数：每月1日打 tag
TODAY=$(date +%d)
TAG_ARGS=()

if [[ "$TODAY" == "01" ]]; then
  MONTH_TAG="monthly-$(date +%Y%m)"
  TAG_ARGS=(--tag "$MONTH_TAG")
  echo "Monthly backup detected, adding tag: $MONTH_TAG"
fi

# 默认排除项：跳过所有 .git 文件夹
EXCLUDE_ARGS=(--exclude .git)

# 构建仓库列表：本地 + 远程
ALL_REPOS=()
if [[ "$LOCAL_REPO_EXISTS" == "true" ]]; then
  ALL_REPOS+=("$LOCAL_REPO_URL")
fi
ALL_REPOS+=("${REMOTE_REPOS[@]}")

if [[ ${#ALL_REPOS[@]} -eq 0 ]]; then
  echo "ERROR: No repositories available for backup"
  exit 1
fi

# 逐个仓库备份
for repo in "${ALL_REPOS[@]}"; do
  echo "------------------------------------------------"
  echo "Repository: $repo"

  if ! restic -r "$repo" snapshots >/dev/null 2>&1; then
    echo "ERROR: Repository not initialized. Run '$(basename "$0") --init' first."
    restic -r "$repo" snapshots 2>&1 | tail -5
    continue
  fi

  restic backup -r "$repo" "${TAG_ARGS[@]}" "${EXCLUDE_ARGS[@]}" "${BACKUP_SOURCES[@]}"
done

echo "------------------------------------------------"
echo "Backup complete!"
