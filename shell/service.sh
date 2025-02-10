#!/usr/bin/env bash

#
# Description: 设置 systemd 服务
#
# UpdatedAt: 2025-02-10
set -euo pipefail

exec 3>&1

script_name=$(basename "$0")

# 设置颜色（如果终端支持）
if [ -t 1 ] && command -v tput &>/dev/null; then
    ncolors=$(tput colors || echo 0)
    if [ "$ncolors" -ge 8 ]; then
        bold="$(tput bold)"
        normal="$(tput sgr0)"
        red="$(tput setaf 1)"
        yellow="$(tput setaf 3)"
        cyan="$(tput setaf 6)"
    fi
fi

# 初始化变量
SERVICE_NAME=""
DESCRIPTION=""
EXEC_START=""
NETWORK=""
RESTART=""
WORKING_DIR=""
ENV_VARS=""

# 输出函数
say() { printf "%b\n" "${cyan:-}${script_name}:${normal:-} $1" >&3; }
say_warning() { printf "%b\n" "${yellow:-}${script_name}: Warning: $1${normal:-}" >&3; }
say_err() { printf "%b\n" "${red:-}${script_name}: Error: $1${normal:-}" >&2; exit 1; }

# 显示帮助信息
show_help() {
    cat <<EOF
Set up a systemd service.

${bold}USAGE:${normal}
    ${script_name} [OPTIONS]

${bold}OPTIONS:${normal}
    -h, --help          Show this help message
    -d, --desc          Application description
    -x, --exec          Application exec script
    -s, --service       Application service name
    -w, --workdir       Application working directory
    -r, --restart       Restart delay time
    -n, --net           Enable network dependency
    -e, --environment   Set environment variables (format: "A=a1;B=b1")
EOF
    exit
}

# 解析参数
judgment_parameters() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help ;;
            -d|--desc) shift; [[ $# -gt 0 ]] && DESCRIPTION="$1" ;;
            -x|--exec) shift; [[ $# -gt 0 ]] && EXEC_START="$1" ;;
            -s|--service) shift; [[ $# -gt 0 ]] && SERVICE_NAME="${1,,}" ;; # 转小写
            -r|--restart) shift; [[ $# -gt 0 ]] && RESTART="$1" ;;
            -n|--net) NETWORK="Yes" ;;
            -w|--workdir) shift; [[ $# -gt 0 ]] && WORKING_DIR="$1" ;;
            -e|--environment) shift; [[ $# -gt 0 ]] && ENV_VARS="$1" ;; # 解析环境变量
            *) shift ;; # 忽略未知参数
        esac
        shift
    done
}

# 解析环境变量格式 A=a1;B=b1 转换为 systemd 格式 Environment="A=a1" Environment="B=b1"
parse_environment_vars() {
    [[ -z "$ENV_VARS" ]] && return
    IFS=';' read -ra VAR_PAIRS <<< "$ENV_VARS"
    for VAR in "${VAR_PAIRS[@]}"; do
        echo "Environment=\"$VAR\""
    done
}

# 主逻辑
main() {
    # 解析参数
    judgment_parameters "$@"

    # 参数检查
    [[ -z "$SERVICE_NAME" || -z "$EXEC_START" || -z "$DESCRIPTION" ]] && say_err "Missing required parameters."

    SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

    # 生成 systemd 服务文件
    {
        echo "[Unit]"
        echo "Description=$DESCRIPTION"
        [[ -n "$NETWORK" ]] && echo -e "After=network.target syslog.target\nWants=network.target"

        echo -e "\n[Service]"
        echo "Type=simple"
        [[ -n "$WORKING_DIR" ]] && echo "WorkingDirectory=$WORKING_DIR"
        echo "ExecStart=$EXEC_START"
        [[ -n "$RESTART" ]] && echo -e "Restart=always\nRestartSec=$RESTART"
        parse_environment_vars

        echo -e "\n[Install]"
        echo "WantedBy=multi-user.target"
    } | tee "$SERVICE_PATH" >/dev/null

    # 重新加载 systemd 并启用服务
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME"

    say "Service '$SERVICE_NAME' has been installed and started successfully."
}

# 执行主逻辑
main "$@"
