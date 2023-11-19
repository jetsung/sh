#!/usr/bin/env bash

######
##
## create systemd service
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

    \e[1;32m-d, --desc\e[m
                Application description  

    \e[1;32m-e, --exec\e[m
                Application exec script           

    \e[1;32m-s, --service\e[m
                Application service name       

    \e[1;32m-w, --workdir\e[m
                Application working directory   

    \e[1;32m-r, --restart\e[m
                Restart time  

    \e[1;32m-n, --net\e[m
                Network         
\n" "${script_name##*/}"
    exit
}

SERVICE_NAME=""
DESCRIPTION=""
EXEC_START=""
NETWORK=""
RESTART=""
WORKING_DIR=""

for ARG in "$@"; do
    case "${ARG}" in
    -h | --help)
        show_help_message
        ;;

    -d | --desc)
        shift
        if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
            DESCRIPTION="${1}"
        fi
        ;;

    -e | --exec)
        shift
        if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
            EXEC_START="${1}"
        fi
        ;;

    -s | --service)
        shift
        if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
            SERVICE_NAME=$(echo "${1}" | tr '[:upper:]' '[:lower:]')
        fi
        ;;

    -r | --restart)
        shift
        if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
            RESTART="${1}"
        fi
        ;;

    -n | --net)
        shift
        NETWORK="Yes"
        ;;

    -w | --workdir)
        shift
        if [ $# -ge 1 ] && [[ "${1}" != -* ]]; then
            WORKING_DIR="${1}"
        fi
        ;;

    *)
        shift
        ;;
    esac
done

if [ -z "$SERVICE_NAME" ] || [ -z "$EXEC_START" ] || [ -z "$DESCRIPTION" ]; then
    say_err "miss params"
fi

SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME.service"

tee "$SERVICE_PATH" >/dev/null <<-EOF
[Unit]
Description = $DESCRIPTION
EOF

if [[ -n "$NETWORK" ]]; then
    tee -a "$SERVICE_PATH" >/dev/null <<-EOF
After = network.target syslog.target
Wants = network.target
EOF
fi

tee -a "$SERVICE_PATH" >/dev/null <<-EOF

[Service]
Type = simple
EOF

if [[ -n "$WORKING_DIR" ]]; then
    tee -a "$SERVICE_PATH" >/dev/null <<-EOF
WorkingDirectory = $WORKING_DIR
EOF
fi

tee -a "$SERVICE_PATH" >/dev/null <<-EOF
ExecStart = $EXEC_START
EOF

if [[ -n "$RESTART" ]]; then
    tee -a "$SERVICE_PATH" >/dev/null <<-EOF
Restart = always
RestartSec = $RESTART
EOF
fi

tee -a "$SERVICE_PATH" <<-EOF

[Install]
WantedBy = multi-user.target
EOF

systemctl daemon-reload

systemctl start "$SERVICE_NAME"

systemctl enable "$SERVICE_NAME"
