#!/usr/bin/env bash

######
##
## create desktop files
##
######

set -e
set -u
set -o pipefail

exec 3>&1

script_name=$(basename "$0")

if [ -t 1 ] && command -v tput >/dev/null; then
  ncolors=$(tput colors || echo 0)
  if [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
    bold="$(tput bold || echo)"
    normal="$(tput sgr0 || echo)"
    black="$(tput setaf 0 || echo)"
    red="$(tput setaf 1 || echo)"
    green="$(tput setaf 2 || echo)"
    yellow="$(tput setaf 3 || echo)"
    blue="$(tput setaf 4 || echo)"
    magenta="$(tput setaf 5 || echo)"
    cyan="$(tput setaf 6 || echo)"
    white="$(tput setaf 7 || echo)"
  fi
fi

say_warning() {
  printf "%b\n" "${yellow:-}${script_name}: Warning: $1${normal:-}" >&3
}

say_err() {
  printf "%b\n" "${red:-}${script_name}: Error: $1${normal:-}" >&2
  exit 1
}

say() {
  printf "%b\n" "${cyan:-}${script_name}:${normal:-} $1" >&3
}

# show help message
show_help_message() {
  printf "Set systemd service

\e[1;33mUSAGE:\e[m
    \e[1;32m%s\e[m [OPTIONS] <SUBCOMMANDS>

\e[1;33mOPTIONS:\e[m
    \e[1;32m-h, --help\e[m
                Print help information.

    \e[1;32m-e, --exec\e[m
                Application exec script           

    \e[1;32m-i, --icon\e[m
                Application icon  
                
    \e[1;32m-n, --name\e[m
                Application name               
\n" "${script_name##*/}"
  exit
}

file_path() {
  local PARAM="$1"

  local PRE="${PARAM%%/*}"
  local SUF="${PARAM#*/}"

  CURRENT=$(pwd)
  __FILE_PATH="$PARAM"

  # 根据前缀更新路径
  case "$PRE" in
  "~") ;; # 变量脚本已自动加 HOME
  "") ;;  # 已经在前面赋值

  "..") # 只支持一级父目录
    PARENT=$(dirname "$CURRENT")
    __FILE_PATH="$PARENT/$SUF"
    ;;

  ".")
    __FILE_PATH="$CURRENT/$SUF"
    ;;

  *)
    __FILE_PATH="$CURRENT/$SUF"
    ;;
  esac
}

SERVICE_NAME=""
ICON=""
EXEC_START=""
COMMENT=""

__FILE_PATH=""

for ARG in "$@"; do
  case "$ARG" in
  -h | --help)
    show_help_message
    ;;

  -e | --exec)
    shift
    if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
      file_path "${1}"
      EXEC_START="$__FILE_PATH"
    fi
    ;;

  -i | --icon)
    shift
    if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
      file_path "${1}"
      ICON="$__FILE_PATH"
    fi
    ;;

  -n | --name)
    shift
    if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
      COMMENT="${1}"
      SERVICE_NAME=$(echo "${COMMENT,,}" | awk '{print $1}')
    fi
    ;;

  *)
    shift
    ;;
  esac
done

if [ -z "$SERVICE_NAME" ] || [ -z "$EXEC_START" ]; then
  say_err "miss params"
fi

if [ ! -d "$HOME/.local/share/applications" ]; then
  say_err "miss $HOME/.local/share/applications"
fi

SERVICE_PATH="$HOME/.local/share/applications/$SERVICE_NAME.desktop"

tee "$SERVICE_PATH" <<-EOF
[Desktop Entry]
Exec=$EXEC_START
Icon=$ICON
Name=$SERVICE_NAME
Comment=$COMMENT
Type=Application
Terminal=false
EOF

[ -n "$ICON" ] || sed -i '/Icon/d' "$SERVICE_PATH"

chmod +x "$SERVICE_PATH"
