#!/usr/bin/env bash

#============================================================
# File: code-migrate.sh
# Description: Git 裸仓库多平台自动备份推送脚本
# URL: https://fx4.cn/JKjOWe
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-01-18
# UpdatedAt: 2026-01-18
#============================================================

if [[ -n "$DEBUG" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 默认配置
TOKEN=""
URL=""
MODE="https"
GIT_PLATFORM=""
DRY_RUN=false
VERBOSE=false
TOKEN_FILE="token.txt"
BACKUP_DIR="." # 默认为当前目录，寻找 .git 仓库

# 全局计数器
SUCCESS_COUNT=0
FAILURE_COUNT=0

# 输出错误信息并退出
error_exit() {
    echo -e "\033[31merror: $1\033[0m" >&2
    exit 1
}

# 警告信息
warn() {
    echo -e "\033[33m$1\033[0m" >&2
}

# 提示信息
tip() {
    echo -e "\033[32m$1\033[0m" >&2
}

# 调试信息
debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "\033[34mdebug: $1\033[0m" >&2
    fi
}

# --- API 工具函数 ---

# 通用请求函数
do_request() {
    local method="$1"
    local api_url="$2"
    local token="$3"
    local platform="$4"
    local data="${5:-}"
    
    local headers=("-H" "Content-Type: application/json")
    
    case "$platform" in
        "gitlab")
            headers+=("-H" "PRIVATE-TOKEN: $token")
            ;;
        "github")
            headers+=("-H" "Authorization: token $token")
            ;;
        "gitea")
            headers+=("-H" "Authorization: token $token")
            ;;
        *)
            headers+=("-H" "Authorization: Bearer $token")
            ;;
    esac

    debug "API REQ: $method $api_url"
    if [[ "$DRY_RUN" == "true" ]]; then
        case "$api_url" in
            */user) echo "{\"username\": \"dry_run_user\", \"login\": \"dry_run_user\"}" ;; 
            */groups/*|*/orgs/*) echo "{\"id\": 123, \"name\": \"dry_run_org\"}" ;; 
            */projects/*|*/repos/*) echo "{\"id\": 456, \"http_url_to_repo\": \"${api_url}.git\", \"clone_url\": \"${api_url}.git\"}" ;; 
            *) echo "{\"status\": \"dry_run_ok\"}" ;; 
        esac
        return 0
    fi

    if [[ -n "$data" ]]; then
        curl -s -X "$method" "$api_url" "${headers[@]}" -d "$data"
    else
        curl -s -X "$method" "$api_url" "${headers[@]}"
    fi
}

# 获取当前用户名
get_current_username() {
    local base_url="$1"
    local platform="$2"
    local token="$3"
    local api_url=""

    case "$platform" in
        "github") api_url="https://api.github.com/user" ;; 
        "gitlab") api_url="${base_url}/api/v4/user" ;; 
        "gitea")  api_url="${base_url}/api/v1/user" ;; 
        "gitcode") api_url="https://api.gitcode.com/api/v5/user" ;; 
    esac

    local res
    res=$(do_request "GET" "$api_url" "$token" "$platform")
    echo "$res" | jq -r '.username // .login // empty'
}

# 检查并创建组织/群组
ensure_namespace() {
    local base_url="$1"
    local platform="$2"
    local token="$3"
    local owner="$4"
    local current_user="$5"

    if [[ "${owner,,}" == "${current_user,,}" ]]; then
        return 0
    fi

    local api_url=""
    local check_url=""
    local create_data=""

    case "$platform" in
        "gitlab")
            local enc_owner="${owner//\//%2F}"
            check_url="${base_url}/api/v4/groups/${enc_owner}"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                return 0
            fi
            tip "创建 GitLab 群组: $owner"
            create_data=$(jq -n --arg name "$owner" --arg path "$owner" '{name: $name, path: $path, visibility: "private"}')
            do_request "POST" "${base_url}/api/v4/groups" "$token" "$platform" "$create_data" > /dev/null
            ;;
        "github")
            check_url="https://api.github.com/orgs/$owner"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                return 0
            fi
            warn "警告: GitHub 组织 $owner 不存在。GitHub 不支持通过 API 直接创建组织，请手动创建。"
            return 1
            ;;
        "gitea")
            check_url="${base_url}/api/v1/orgs/$owner"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                return 0
            fi
            tip "创建 Gitea 组织: $owner"
            create_data=$(jq -n --arg username "$owner" '{username: $username, visibility: "private"}')
            do_request "POST" "${base_url}/api/v1/orgs" "$token" "$platform" "$create_data" > /dev/null
            ;;
        "gitcode")
            check_url="https://api.gitcode.com/api/v5/orgs/$owner"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                return 0
            fi
            warn "警告: GitCode 组织 $owner 不存在。GitCode 不支持通过 API 直接创建组织，请手动创建。"
            return 1
            ;;
    esac
}

# 检查并创建项目
ensure_project() {
    local base_url="$1"
    local platform="$2"
    local token="$3"
    local owner="$4"
    local project="$5"
    local current_user="$6"

    local check_url=""
    local create_url=""
    local create_data=""
    local is_org=true
    [[ "${owner,,}" == "${current_user,,}" ]] && is_org=false

    case "$platform" in
        "gitlab")
            local full_path="${owner}/${project}"
            local enc_path="${full_path//\//%2F}"
            check_url="${base_url}/api/v4/projects/${enc_path}"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                echo "$res" | jq -r '.http_url_to_repo'
                return
            fi
            
            tip "创建 GitLab 项目: $full_path"
            if [[ "$is_org" == "true" ]]; then
                local enc_owner="${owner//\//%2F}"
                local ns_id
                ns_id=$(do_request "GET" "${base_url}/api/v4/groups/${enc_owner}" "$token" "$platform" | jq -r '.id')
                if [[ -z "$ns_id" || "$ns_id" == "null" ]]; then
                    warn "无法获取群组 $owner 的 ID"
                    return 1
                fi
                create_data=$(jq -n --arg name "$project" --arg ns "$ns_id" '{name: $name, namespace_id: $ns, visibility: "private"}')
            else
                create_data=$(jq -n --arg name "$project" '{name: $name, visibility: "private"}')
            fi
            res=$(do_request "POST" "${base_url}/api/v4/projects" "$token" "$platform" "$create_data")
            echo "$res" | jq -r '.http_url_to_repo'
            ;;
        "github")
            check_url="https://api.github.com/repos/${owner}/${project}"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                echo "$res" | jq -r '.clone_url'
                return
            fi

            tip "创建 GitHub 仓库: ${owner}/${project}"
            create_data=$(jq -n --arg name "$project" '{name: $name, private: true}')
            if [[ "$is_org" == "true" ]]; then
                create_url="https://api.github.com/orgs/${owner}/repos"
            else
                create_url="https://api.github.com/user/repos"
            fi
            res=$(do_request "POST" "$create_url" "$token" "$platform" "$create_data")
            echo "$res" | jq -r '.clone_url'
            ;;
        "gitea")
            check_url="${base_url}/api/v1/repos/${owner}/${project}"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                echo "$res" | jq -r '.clone_url'
                return
            fi

            tip "创建 Gitea 仓库: ${owner}/${project}"
            create_data=$(jq -n --arg name "$project" '{name: $name, private: true}')
            if [[ "$is_org" == "true" ]]; then
                create_url="${base_url}/api/v1/orgs/${owner}/repos"
            else
                create_url="${base_url}/api/v1/user/repos"
            fi
            res=$(do_request "POST" "$create_url" "$token" "$platform" "$create_data")
            echo "$res" | jq -r '.clone_url'
            ;;
        "gitcode")
            check_url="https://api.gitcode.com/api/v5/repos/${owner}/${project}"
            local res
            res=$(do_request "GET" "$check_url" "$token" "$platform")
            if [[ "$(echo "$res" | jq -r '.id // empty')" != "" ]]; then
                echo "$res" | jq -r '.http_url_to_repo'
                return
            fi

            tip "创建 GitCode 仓库: ${owner}/${project}"
            create_data=$(jq -n --arg name "$project" '{name: $name, private: true}')
            if [[ "$is_org" == "true" ]]; then
                create_url="https://api.gitcode.com/api/v5/orgs/${owner}/repos"
            else
                create_url="https://api.gitcode.com/api/v5/user/repos"
            fi
            res=$(do_request "POST" "$create_url" "$token" "$platform" "$create_data")
            full_name=$(echo "$res" | jq -r '.full_name')
            echo "https://gitcode.com/${full_name}.git"
            ;;
    esac
}

# 打印帮助信息
usage() {
    cat <<EOF
用法: $0 [options] 

选项:
  -t, --token <token>       个人访问令牌 (API 调用)
  -u, --url <url>           目标平台基础 URL (例如 https://gitlab.com)
  -m, --mode <https|ssh>    推送模式 (默认: https)
  -g, --git <platform>      平台类型 (gitlab|gitea|github|gitcode)
  -f, --file <token_file>   指定 token.txt 文件 (默认: token.txt)
  -d, --dir <backup_dir>    本地裸仓库根目录 (默认: .)
  --dry-run                 只打印命令，不真正执行推送和创建
  --verbose                 显示详细调试信息
  -h, --help                显示此帮助信息

token.txt 格式:
  <base_url> <platform_type> <token_or_env_var> <push_mode>
EOF
    exit 0
}

# 解析参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--token) TOKEN="$2"; shift ;; 
        -u|--url) URL="$2"; shift ;; 
        -m|--mode) MODE="$2"; shift ;; 
        -g|--git) GIT_PLATFORM="$2"; shift ;; 
        -f|--file) TOKEN_FILE="$2"; shift ;; 
        -d|--dir) BACKUP_DIR="$2"; shift ;; 
        --dry-run) DRY_RUN=true ;; 
        --verbose) VERBOSE=true ;; 
        -h|--help) usage ;; 
        *) echo "未知参数: $1"; usage ;; 
    esac
    shift
done

# 核心逻辑：处理单个目标
process_target() {
    local target_url="$1"
    local target_platform="$2"
    local target_token_raw="$3"
    local target_mode="${4:-$MODE}"
    local target_token=""

    # 处理 token 环境变量
    if [[ "$target_token_raw" == \$* ]]; then
        local env_var_name="${target_token_raw#\$}"
        target_token="${!env_var_name:-}"
        if [[ -z "$target_token" ]]; then
            warn "警告: 环境变量 $env_var_name 为空，跳过目标 $target_url"
            return 1
        fi
    else
        target_token="$target_token_raw"
    fi

    tip "===================================================="
    tip "正在处理目标: $target_url ($target_platform) [Mode: $target_mode]"
    tip "===================================================="

    local current_user
    current_user=$(get_current_username "$target_url" "$target_platform" "$target_token")
    if [[ -z "$current_user" ]]; then
        warn "错误: 无法获取平台 $target_platform 的当前用户名，请检查 Token 权限。"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        return 1
    fi
    tip "当前登录用户: $current_user"

    # 遍历本地裸仓库 - 使用进程替换避免子 shell 导致变量失效
    while read -r repo_path; do
        local rel_path="${repo_path#"$BACKUP_DIR"/}"
        local path_no_git="${rel_path%.git}"
        local owner
        owner=$(dirname "$path_no_git")
        local project
        project=$(basename "$path_no_git")

        debug "处理仓库: $rel_path -> Owner: $owner, Project: $project"

        ensure_namespace "$target_url" "$target_platform" "$target_token" "$owner" "$current_user" || { FAILURE_COUNT=$((FAILURE_COUNT + 1)); continue; }

        local remote_url
        remote_url=$(ensure_project "$target_url" "$target_platform" "$target_token" "$owner" "$project" "$current_user")
        
        if [[ -z "$remote_url" || "$remote_url" == "null" ]]; then
            warn "错误: 无法确保项目 $owner/$project 在平台 $target_platform 上存在。"
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            continue
        fi

        local push_url="$remote_url"
        if [[ "$target_mode" == "https" ]]; then
            local url_no_proto="${remote_url#https://}"
            case "$target_platform" in
                "gitlab")
                    push_url="https://oauth2:${target_token}@${url_no_proto}"
                    ;;
                *)
                    push_url="https://${current_user}:${target_token}@${url_no_proto}"
                    ;;
            esac
        elif [[ "$target_mode" == "ssh" ]]; then
            # 转换 https://domain.com/path/repo.git 为 git@domain.com:path/repo.git
            local host_path="${remote_url#https://}"
            local host="${host_path%%/*}"
            local path="${host_path#*/}"
            push_url="git@${host}:${path}"
        fi

        local log_url="$remote_url"
        [[ "$target_mode" == "ssh" ]] && log_url="$push_url"

        tip "推送仓库: $rel_path -> $log_url ($target_mode)"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] git -C \"$repo_path\" push --mirror \"$push_url\""
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            if git -C "$repo_path" push --mirror "$push_url"; then
                tip "推送成功: $rel_path -> $remote_url"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                echo "========"
            else
                warn "推送失败: $rel_path"
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
            fi
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 2 -mindepth 2 -type d -name "*.git")
}

# 如果指定了命令行参数，则处理单个目标；否则读取 token.txt
if [[ -n "$URL" && -n "$GIT_PLATFORM" && -n "$TOKEN" ]]; then
    process_target "$URL" "$GIT_PLATFORM" "$TOKEN"
elif [[ -f "$TOKEN_FILE" ]]; then
    while read -r line || [[ -n "$line" ]]; do
        if [[ -z "${line// }" || "$line" == "#"* ]]; then
            continue
        fi
        
        read -r b_url p_type t_raw m_type <<< "$line"
        
        if [[ -z "$b_url" || -z "$p_type" || -z "$t_raw" ]]; then
            warn "警告: token.txt 行格式错误: $line"
            continue
        fi

        if [[ -z "$m_type" ]]; then
            m_type="https"
        fi
        
        process_target "$b_url" "$p_type" "$t_raw" "$m_type"
    done < "$TOKEN_FILE"
else
    if [[ ! -f "$TOKEN_FILE" ]]; then
        error_exit "未提供参数且未找到 $TOKEN_FILE 文件。"
    else
        error_exit "请提供 --url, --git 和 --token 参数，或配置正确的 $TOKEN_FILE。"
    fi
fi

tip "===================================================="
tip "推送任务完成!"
tip "成功: $SUCCESS_COUNT"
tip "失败: $FAILURE_COUNT"
tip "===================================================="