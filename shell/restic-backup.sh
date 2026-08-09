#!/usr/bin/env bash
#============================================================
# File: restic-backup.sh
# Description: Restic 备份工具 - 支持本地/远程多仓库备份、自动触发（登录/关机/cron）、快照管理
# URL: https://fx4.cn/resticbackup
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.6.0
# UpdatedAt: 2026-07-01
#============================================================

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

# 从 sources.txt 读取备份目标（每行一个，支持 $HOME 展开）
BACKUP_SOURCES=()
if [[ -f "$SOURCES_FILE" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && BACKUP_SOURCES+=("$(eval echo "$line")")
  done < "$SOURCES_FILE"
fi

# 动态添加所有 Claude 相关的 settings 配置文件
# for f in $HOME/.config/claude/settings.*.json; do
#   [ -e "$f" ] && BACKUP_SOURCES+=("$f")
# done

# 安装登录触发服务 (用户级)
install_login() {
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

# 安装关机触发服务 (系统级，需要 sudo)
install_shutdown() {
  # 复制脚本到系统目录（绕过 SELinux）
  sudo cp -f "$SCRIPT_PATH" /usr/local/bin/restic-backup.sh 2>/dev/null || true
  sudo chmod +x /usr/local/bin/restic-backup.sh
  local system_script="/usr/local/bin/restic-backup.sh"

  local env_line=""
  if [[ -f "$ENV_FILE" ]]; then
    env_line="EnvironmentFile=$ENV_FILE"
  fi

  sudo tee /etc/systemd/system/restic-backup-shutdown.service <<EOF
[Unit]
Description=Restic Backup on Shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=$system_script
RemainAfterExit=yes
User=$(whoami)
$env_line

[Install]
WantedBy=shutdown.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable restic-backup-shutdown.service
  echo "Shutdown service installed and enabled."
}

# 卸载所有触发服务
uninstall_all() {
  # 用户级 - 登录服务
  systemctl --user disable restic-backup-login.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/restic-backup-login.service"
  systemctl --user daemon-reload

  # 系统级 - 关机服务
  sudo systemctl disable restic-backup-shutdown.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/restic-backup-shutdown.service
  sudo systemctl daemon-reload

  # cron 任务
  crontab -l 2>/dev/null | grep -v "$(basename "$SCRIPT_PATH")" | crontab - 2>/dev/null || true

  echo "All services uninstalled."
}

# 安装 cron 定时任务（凌晨随机时间）
install_cron() {
  local hour=$((RANDOM % 6))      # 0-5
  local min=$((RANDOM % 60))      # 0-59
  local cron_line="$min $hour * * * $SCRIPT_PATH >> /var/log/restic-backup.log 2>&1"

  # 移除旧的 restic-backup cron 条目，再添加新的
  (crontab -l 2>/dev/null | grep -v "$(basename "$SCRIPT_PATH")"; echo "$cron_line") | crontab -

  echo "Cron job installed: $cron_line"
}

# 显示帮助
show_help() {
  cat <<EOF
用法: $(basename "$0") [选项]

选项:
  -h, --help            显示此帮助信息
  --init [目标]         初始化指定的备份仓库
  --show [目标]         查看快照
  --prune [目标]        清理旧快照（保留最近3个 + 每月1日tag）
  --install             安装登录和关机自动备份服务
  --install-login       仅安装登录时自动备份服务
  --install-shutdown    仅安装关机时自动备份服务 (需要 sudo)
  --cron                添加 cron 定时任务（凌晨随机时间，日志写入 /var/log/restic-backup.log）
  --sync                同步脚本到 /usr/local/bin/ (需要 sudo)
  --uninstall           卸载所有自动备份服务

备份行为:
  所有可用仓库（本地 + 远程）均执行备份，快照独立

配置文件:
  $REPOS_FILE      远程仓库列表（每行一个）
  $SOURCES_FILE    备份目标列表（每行一个，支持 \$HOME）
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
-h | --help)
  show_help
  exit 0
  ;;
--init)
  init_repos "${2:-}"
  exit 0
  ;;
--show)
  show_snapshots "${2:-}"
  exit 0
  ;;
--sync)
  sudo cp -f "$SCRIPT_PATH" /usr/local/bin/restic-backup.sh
  echo "Synced to /usr/local/bin/restic-backup.sh"
  exit 0
  ;;
--prune)
  prune_snapshots "${2:-}"
  exit 0
  ;;
--install|--install-login|--install-shutdown|--uninstall)
  if [[ "$EUID" -eq 0 ]]; then
    echo "ERROR: This option must be run as a normal user (not root)."
    echo "Intended for desktop environments, not VPS/servers."
    exit 1
  fi
  case "${1:-}" in
  --install)
    install_login
    install_shutdown
    ;;
  --install-login)
    install_login
    ;;
  --install-shutdown)
    install_shutdown
    ;;
  --uninstall)
    uninstall_all
    ;;
  esac
  exit 0
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
    continue
  fi

  restic backup -r "$repo" "${TAG_ARGS[@]}" "${BACKUP_SOURCES[@]}"
done

echo "------------------------------------------------"
echo "Backup complete!"
