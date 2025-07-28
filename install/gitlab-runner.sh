#!/usr/bin/env bash

#============================================================
# File: gitlab-runner.sh
# Description: 安装 GitLab Runner
# URL: https://s.fx4.cn/gitlab-runner
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-14
# UpdatedAt: 2025-03-14
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

check_url_connection() {
    _url="${1:-}"
    if [[ -z "$_url" ]]; then
        return 1
    fi

    if [[ -n "${CN:-}" ]]; then
        return 1 # 手动指定
    fi    

    _check_url=$(echo "$_url" | cut -d '/' -f 1-3)
    if [[ $(curl -s -m 3 -o /dev/null -w "%{http_code}" "$_check_url") != "200" ]]; then
        return 0 # 联通
    fi
    return 1 # 不能联通
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
    local _url="$1"
    if [[ -n "$NO_HTTPS" ]]; then
        # shellcheck disable=SC2001
        echo "$_url" | sed 's|https:/||2'

    else 
        echo "$_url"
    fi
}

get_system_info() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "deepin" ]]; then
            echo "debian"
        elif [[ "$ID" == "centos" || "$ID" == "fedora" || "$ID" == "redhat" ]]; then
            echo "redhat"
        else
            echo "unknown"
        fi
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    else
        echo "unknown"
    fi    
}

do_install() {
    case "${METHOD,,}" in
        "b" | "binary")
            install_with_binary
            ;;

        "d" | "docker")
            install_with_docker
            ;;

        "p" | "package")
            install_with_package
            ;;

        "s" | "shell" | *)
            install_with_shell
            ;;
    esac
}

install_with_shell() {
    echo "Installing GitLab Runner with shell (${SYSTEM})..."

    local _method=""
    if [[ "$SYSTEM" == "debian" ]]; then
        _method="deb"
    elif [[ "$SYSTEM" == "redhat" ]]; then
        _method="rpm"
    else
        echo "Unsupported system: $SYSTEM"
        exit 1
    fi

    local _download_url="${CDN_URL}https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.${_method}.sh"
    _download_url=$(do_remove_https "$_download_url") 
    curl -L "$_download_url" | sudo_exec bash
}

install_with_package() {
    echo "Installing GitLab Runner with package (${SYSTEM})..."

    if [[ "$SYSTEM" == "debian" ]]; then
        local _base_url="${CDN_URL}https://gitlab-runner-downloads.s3.amazonaws.com/latest/deb/"
        _base_url=$(do_remove_https "$_base_url") 
        local _pkgs="-helper-images _${ARCH} "
        for pkg in $_pkgs; do
            local _download_url="${_base_url}gitlab-runner${pkg}.deb"
            local _pkg_file="/tmp/gitlab-runner${pkg}.deb"
            curl -L --output "$_pkg_file" "$_download_url"
            sudo_exec dpkg -i "$_pkg_file"
            rm -f "$_pkg_file"
        done
    elif [[ "$SYSTEM" == "redhat" ]]; then
        local _base_url="${CDN_URL}https://gitlab-runner-downloads.s3.amazonaws.com/latest/rpm/"    
        _base_url=$(do_remove_https "$_base_url")        
        local _pkgs="-helper-images _${ARCH}"
        for pkg in $_pkgs; do
            local _download_url="${_base_url}gitlab-runner${pkg}.rpm"
            local _pkg_file="/tmp/gitlab-runner${pkg}.rpm"
            curl -L --output "$_pkg_file" "$_download_url"
            sudo_exec rpm -i "$_pkg_file"
            rm -f "$_pkg_file"
        done    
    else
        echo "Unsupported system: $SYSTEM"
        exit 1
    fi
}

install_with_binary() {
    echo "Installing GitLab Runner with binary (${SYSTEM} ${OS} ${ARCH})..."

    local _download_url="${CDN_URL}https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-${OS}-${ARCH}" 
    _download_url=$(do_remove_https "$_download_url") 
    sudo_exec curl -L --output /usr/local/bin/gitlab-runner "$_download_url"
    sudo_exec chmod +x /usr/local/bin/gitlab-runner

    if [[ -n "${INIT:-}" ]]; then
        sudo_exec useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
        sudo_exec gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
        sudo_exec gitlab-runner start  
    fi  
}

install_with_docker() {
    echo "Installing GitLab Runner with Docker..."

    if [[ "$USER_ID" -ne 0 ]]; then
        SOCKET_PATH="/run/user/${USER_ID}/docker.sock"
    fi

    cat <<EOF > docker-compose.yml
services:
  gitlab-runner:
    image: gitlab/gitlab-runner:latest
    container_name: gitlab-runner
    restart: unless-stopped
    environment:
      - TZ=CST-8
      - DOCKER_TLS_CERTDIR=""
    volumes:
    - ${SOCKET_PATH:-/var/run/docker.sock}:/var/run/docker.sock
EOF

    if [[ -z "${VOLUME:-}" ]]; then
        {
            echo '    - gitlab-runner-config:/etc/gitlab-runner'
            echo ''
            echo 'volumes:'
            echo '  gitlab-runner-config:'
        } >> docker-compose.yml
    else 
            echo "    - ${VOLUME}:/etc/gitlab-runner" >> docker-compose.yml
    fi

    docker run --rm gitlab/gitlab-runner --version

    write_register_script "docker exec gitlab-runner"

    exit 0
}

write_register_script() {
    echo "Writing register script..."

    DOCKER_EXEC="${1:-}"

    cat <<'EOF' > register.sh
#!/usr/bin/env bash

set -euo pipefail

judgment_parameters() {
  while getopts "d:t:u:" opt; do
    case "$opt" in
      d)
        DESCRIPTION="$OPTARG"
        ;;

      t)
        RUNNER_TOKEN="$OPTARG"
        ;;
      u)
        GITLAB_URL="$OPTARG"
        ;;

      \?)
        echo "Usage: $0 [-d <descriptioin>] [-t <runner token>] [-u <gitlab url>]"
        exit 1
        ;;
    esac
  done
}

main() {
    judgment_parameters "$@"

    REGISTER_URL=${GITLAB_URL:-https://gitlab.com/}

    if [[ -z "${RUNNER_TOKEN:-}" ]]; then
        echo "Please enter the registration token:"
        read -r RUNNER_TOKEN
    fi

    if [[ -z "${RUNNER_TOKEN:-}" ]]; then
        echo "Registration token cannot be empty."
        exit 1
    fi

    DESCRIPTION="${DESCRIPTION:-My Docker Runner}"
EOF

    if [[ -n "${DOCKER_EXEC:-}" ]]; then
        echo "    ${DOCKER_EXEC} gitlab-runner register \\" >> register.sh
    else
        echo "    gitlab-runner register \\" >> register.sh
    fi

    cat <<'EOF' >> register.sh
        --non-interactive \
        --url "$REGISTER_URL" \
        --token "$RUNNER_TOKEN" \
        --executor "docker" \
        --docker-image docker:latest \
        --docker-privileged true \
        --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
        --description "$DESCRIPTION"
}

main "$@"
EOF

    chmod +x register.sh    
}

judgment_parameters() {
  while getopts "im:v:" opt; do
    case "$opt" in
      i)
        INIT=1
        ;;

      m)
        METHOD="$OPTARG"
        ;;
      v)
        VOLUME="$OPTARG"
        ;;

      \?)
        echo "Usage: $0 [-i] [-m <b|binary|d|docker|p|package|s|shell>] [-v <volume>]"
        exit 1
        ;;
    esac
  done
}

main() {
    judgment_parameters "$@"

    if ! check_in_china; then
        CDN_URL=""
    fi

    NO_HTTPS=$(check_remove_https "$CDN_URL")

    SYSTEM="$(get_system_info)"

    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"
    case "$ARCH" in
        "x86_64")
            ARCH="amd64"
            ;;
        "aarch64")
            ARCH="arm64"
            ;;
    esac

    METHOD="${METHOD:-s}"

    do_install

    echo ""

    if ! check_is_command "gitlab-runner"; then
        echo "GitLab Runner has not been installed successfully."
        echo ""
        exit 1
    fi

    write_register_script

    echo "GitLab Runner has been installed successfully!"
    echo ""
    gitlab-runner --version
    echo ""
}

main "$@"
