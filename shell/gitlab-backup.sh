#!/usr/bin/env bash

#
# GitLab 账号源码仓库备份
# https://gitlab.com/gitlab-org/gitlab/-/blob/master/doc/api/openapi/openapi_v2.yaml
#
# 依赖:
#   - jq
#
# 用法:
#   1. 安装 jq 命令
#   2. 配置 TOKEN 和 URL
#   3. 执行脚本
#
# 示例:
#   gitlab-backup.sh --help
#
# lastmod: 2025-03-04
#

set -euo pipefail
# set -eux

DEFAULT_URL="https://gitlab.com"
API_VERSION="/api/v4"

# 输出错误信息并退出
error_exit() {
    echo -e "\033[31merror: $1\033[0m" >&2
    exit 1
}

warn() {
    echo -e "\033[33m$1\033[0m"
}

tip() {
    echo -e "\033[32m$1\033[0m"
}

# 判断是否为 URL 的函数
is_url() {
    local url="$1"
    # 正则表达式匹配 URL
    if [[ "$url" =~ ^https?://[^[:space:]]+ ]]; then
        return 0  # 是 URL
    else
        return 1  # 不是 URL
    fi
}

# 通用请求函数
do_request() {
    local method="${METHOD:-GET}"
    local update_data="${UPDATE_DATA:-{}}"
    local headers=()

    if [[ -n "$TOKEN" ]]; then
        headers+=("-H" "PRIVATE-TOKEN: $TOKEN")
    else
        error_exit "TOKEN must be set."
    fi

    if [[ "${method^^}" = "GET" ]]; then
        REQUEST_URL=$(echo "${UPDATE_DATA:-}" | jq -r 'to_entries | map("\(.key)=\(.value)") | join("&")')
        API_REQ="${API_REQ}?${REQUEST_URL}"
        update_data="{}"
    fi

    curl -s -X "$method" "$API_REQ" \
        "${headers[@]}" \
        -H "Content-Type: application/json" \
        -d "$update_data"
}

# 获取群组列表
api_group_list() {
    API_REQ="${API_URL}/groups"
    METHOD="GET"
    UPDATE_DATA=$(jq -n \
        --arg statistics "${STATISTICS:-}" \
        --arg skip_groups "${SKIP_GROUPS:-}" \
        --arg all_available "${ALL_AVAILABLE:-}" \
        --arg visibility "${VISIBILITY:-}" \
        --arg search "${SEARCH:-}" \
        --arg min_access_level "${MIN_ACCESS_LEVEL:-}" \
        --arg top_level_only "${TOP_LEVEL_ONLY:-}" \
        --arg repository_storage "${REPOSITORY_STORAGE:-}" \
        --arg marked_for_deletion_on "${MARKED_FOR_DELETION_ON:-}" \
        --arg page "${PAGE:-}" \
        --arg per_page "${PER_PAGE:-}" \
        --arg with_custom_attributes "${WITH_CUSTOM_ATTRIBUTES:-}" \
            '{
                statistics: $statistics,
                skip_groups: $skip_groups,
                all_available: $all_available,
                visibility: $visibility,
                search: $search,
                min_access_level: $min_access_level,
                top_level_only: $top_level_only,
                repository_storage: $repository_storage,
                marked_for_deletion_on: $marked_for_deletion_on,
                page: $page,
                per_page: $per_page,
                with_custom_attributes: $with_custom_attributes
            }
            | with_entries(select(.value != ""))')

    do_request | jq -r '.'
}
group() {
    case "${ACTION:-}" in
        'li' | 'list') 
            # 获取群组列表
            api_group_list
            ;;    
        *)
            error_exit "无效的操作类型."
    esac
}
help_group() {
    case "${ACTION:-}" in
        'ls' | 'list')
cat <<EOF
 用法: $0 -s $(warn "group") --action $(warn "$ACTION") [options]
    $(warn "获取群组列表")

    -h,  --help                             打印帮助信息
            --statistics                    可选,统计信息（默认值：false）
            --skip_groups                   可选,跳过群组，格式：1,2,3,4
            --all_available                 可选,显示可访问的所有组
            --visibility                    可选,可见性，可选值：public, internal, private
            --search                        可选,搜索特定群组
            --owned                         可选,仅获取属于当前用户的群组（默认值：false）
            --order_by                      可选,排序方式（默认值：name）
            --sort                          可选,排序顺序（默认值：asc）
            --min_access_level              可选,最小访问级别
            --top_level_only                可选,仅获取顶级群组
            --repository_storage            可选,按组使用的存储库存储进行过滤
            --marked_for_deletion_on        可选,标记为删除组的日期
            --page                          可选,页数（默认值：1）
            --per_page                      可选,默认页面大小（默认值：20，最大值：100）
            --with_custom_attributes        可选,是否包含自定义属性（默认值：false）
EOF
        ;;     

        *)
cat <<EOF
 用法: $0 -s $(warn "$SELECT") --action [options]

    $(warn "群组")

    -h, --help                 打印帮助信息
    -a, --action               指定操作类型
            ls list            获取群组列表
EOF
        ;;


    esac
}

# 获取项目列表
api_project_list() {
    API_REQ="${API_URL}/projects"
    METHOD="GET"
    UPDATE_DATA=$(jq -n \
        --arg statistics "${STATISTICS:-}" \
        --arg skip_groups "${SKIP_GROUPS:-}" \
        --arg all_available "${ALL_AVAILABLE:-}" \
        --arg visibility "${VISIBILITY:-}" \
        --arg search "${SEARCH:-}" \
        --arg search_namespaces "${SEARCH_NAMESPACES:-}" \
        --arg owned "${OWNED:-}" \
        --arg starred "${STARRED:-}" \
        --arg imported "${IMPORTED:-}" \
        --arg membership "${MEMBERSHIP:-}" \
        --arg with_issues_enabled "${WITH_ISSUES_ENABLED:-}" \
        --arg with_merge_requests_enabled "${WITH_MERGE_REQUESTS_ENABLED:-}" \
        --arg with_programming_language "${WITH_PROGRAMMING_LANGUAGE:-}" \
        --arg min_access_level "${MIN_ACCESS_LEVEL:-}" \
        --arg id_after "${ID_AFTER:-}" \
        --arg id_before "${ID_BEFORE:-}" \
        --arg last_activity_after "${LAST_ACTIVITY_AFTER:-}" \
        --arg last_activity_before "${LAST_ACTIVITY_BEFORE:-}" \
        --arg repository_storage "${REPOSITORY_STORAGE:-}" \
        --arg topic "${TOPIC:-}" \
        --arg topic_id "${TOPIC_ID:-}" \
        --arg updated_before "${UPDATED_BEFORE:-}" \
        --arg updated_after "${UPDATED_AFTER:-}" \
        --arg include_pending_delete "${INCLUDE_PENDING_DELETE:-}" \
        --arg wiki_checksum_failed "${WIKI_CHECKSUM_FAILED:-}" \
        --arg repository_checksum_failed "${REPOSITORY_CHECKSUM_FAILED:-}" \
        --arg include_hidden "${INCLUDE_HIDDEN:-}" \
        --arg marked_for_deletion_on "${MARKED_FOR_DELETION_ON:-}" \
        --arg page "${PAGE:-}" \
        --arg per_page "${PER_PAGE:-}" \
        --arg simple "${SIMPLE:-}" \
            '{
                statistics: $statistics,
                skip_groups: $skip_groups,
                all_available: $all_available,
                visibility: $visibility,
                search: $search,
                search_namespaces: $search_namespaces,
                owned: $owned,
                starred: $starred,
                imported: $imported,
                membership: $membership,
                with_issues_enabled: $with_issues_enabled,
                with_merge_requests_enabled: $with_merge_requests_enabled,
                with_programming_language: $with_programming_language,
                min_access_level: $min_access_level,
                id_after: $id_after,
                id_before: $id_before,
                last_activity_after: $last_activity_after,
                last_activity_before: $last_activity_before,
                repository_storage: $repository_storage,
                topic: $topic,
                topic_id: $topic_id,
                updated_before: $updated_before,
                updated_after: $updated_after,
                include_pending_delete: $include_pending_delete,
                wiki_checksum_failed: $wiki_checksum_failed,
                repository_checksum_failed: $repository_checksum_failed,
                include_hidden: $include_hidden,
                marked_for_deletion_on: $marked_for_deletion_on,
                page: $page,
                per_page: $per_page,
                simple: $simple
            }
            | with_entries(select(.value!= ""))')

    do_request | jq -r '.'

}
project() {
    case "${ACTION:-}" in
        'li' | 'list')
            # 获取群组列表
            api_project_list
            ;;
        *)
            error_exit "无效的操作类型."
    esac
}
help_project() {
    case "${ACTION:-}" in
        'ls' | 'list')
cat <<EOF
用法: $0 -s $(warn "project") --action $(warn "$ACTION") [options]

    $(warn "获取项目列表")

    -h,  --help                              打印帮助信息
            --statistics                     可选, 包含项目统计信息（默认值：false）
            --skip_groups                    可选, 跳过指定的群组，格式：1,2,3,4
            --all_available                  可选, 显示所有可访问的项目（包括私有和公共的）
            --visibility                     可选, 项目可见性， 可选值：private, internal, public
            --search                         可选, 搜索项目的名称或描述
            --search_namespaces              可选, 在搜索时是否包括父命名空间
            --owned                          可选, 仅获取当前用户拥有的项目（默认值：false）
            --starred                        可选, 仅获取当前用户星标的项目（默认值：false）
            --imported                       可选, 仅获取当前用户导入的项目（默认值：false）
            --membership                     可选, 仅获取当前用户作为成员的项目（默认值：false）
            --with_issues_enabled            可选, 是否仅获取启用了问题功能的项目（默认值：false）
            --with_merge_requests_enabled    可选, 是否仅获取启用了合并请求功能的项目（默认值：false）
            --with_programming_language      可选, 限制返回特定编程语言的项目
            --min_access_level               可选, 最小访问级别， 可选值：10, 15, 20, 30, 40, 50
            --id_after                       可选, 限制返回 ID 大于指定值的项目
            --id_before                      可选, 限制返回 ID 小于指定值的项目
            --last_activity_after            可选, 限制返回最后活跃时间在指定时间之后的项目
            --last_activity_before           可选, 限制返回最后活跃时间在指定时间之前的项目
            --repository_storage             可选, 按项目存储分片过滤（仅管理员可用）
            --topic                          可选, 限制返回包含所有指定主题的项目
            --topic_id                       可选, 限制返回具有指定主题 ID 的项目
            --updated_before                 可选, 限制返回最后更新时间在指定时间之前的项目
            --updated_after                  可选, 限制返回最后更新时间在指定时间之后的项目
            --include_pending_delete         可选, 是否包括待删除状态的项目（仅管理员可用）
            --wiki_checksum_failed           可选, 是否仅返回 wiki 校验失败的项目（默认值：false）
            --repository_checksum_failed     可选, 是否仅返回仓库校验失败的项目（默认值：false）
            --include_hidden                 可选, 是否包括隐藏的项目（仅管理员可用）
            --marked_for_deletion_on         可选, 项目标记为删除的日期
            --page                           可选, 当前页数（默认值：1）
            --per_page                       可选, 每页返回的项目数量（默认值：20）
            --simple                         可选, 只返回项目的 ID、URL、名称和路径（默认值：false）
            --with_custom_attributes         可选, 是否返回项目的自定义属性（默认值：false）
EOF
        ;;

        *)
cat <<EOF
用法: $0 -s $(warn "$SELECT") --action [options]

    $(warn "项目")

    -h, --help                 打印帮助信息
    -a, --action               指定操作类型
            ls list            获取项目列表
EOF
        ;;
    esac
}

api_user_current() {
    API_REQ="${API_URL}/user"
    METHOD="GET"
    
    do_request | jq -r '.'
}
user() {
    case "${ACTION:-}" in
        'cu' | 'current')
            # 获取当前用户信息
            api_user_current
            ;;
        *)
            error_exit "无效的操作类型."
    esac
}
help_user() {
    case "${ACTION:-}" in
        *)
cat <<EOF
用法: $0 -s $(warn "$SELECT") --action [options]

    $(warn "用户")

    -h, --help                 打印帮助信息
    -a, --action               指定操作类型
            cu current         获取当前用户信息
EOF
        ;;
    esac
}

# 执行备份
backup() {
    echo ""
    local backup_dir="${BACKUP_DIR:-}"
    local backup_name="${BACKUP_NAME:-}"
    local backup_time
    backup_time=$(date "+%Y%m%d")
    if [[ -z "$backup_dir" ]]; then
        backup_dir="$(pwd)/backup"
    fi
    if [[ -z "$backup_name" ]]; then
        backup_name="gitlab-${backup_time}"
    fi

    # mkdir -p "$backup_dir"
    local backup_path="${backup_dir}/${backup_name}"
    mkdir -p "$backup_path"
    warn "备份路径: $backup_path"
    warn "开始备份"
    echo ""

    pushd "$backup_path" > /dev/null 2>&1
        MODE="${MODE:-https}"
        if [[ "$MODE" != "ssh" ]]; then
            USERNAME=$(api_user_current | jq -r '.username')
            USERNAME_TOKEN="${USERNAME}:${TOKEN}"
        fi

        project_json=$(api_project_list)
        echo "$project_json" | jq -c '.[]' | while read -r project; do
            project_id=$(echo "$project" | jq -r '.id')
            project_name=$(echo "$project" | jq -r '.name')
            project_path=$(echo "$project" | jq -r '.path') 
            path_with_namespace=$(echo "$project" | jq -r '.path_with_namespace')
            description=$(echo "$project" | jq -r '.description')
            http_url_to_repo=$(echo "$project" | jq -r '.http_url_to_repo')
            ssh_url_to_repo=$(echo "$project" | jq -r '.ssh_url_to_repo')
            web_url=$(echo "$project" | jq -r '.web_url')
            project_path_dir=$(dirname "$path_with_namespace")

            tip "项目 ID: $project_id"
            tip "项目名称: $project_name"
            tip "项目路径: $project_path"
            tip "项目路径带命名空间: $path_with_namespace"
            tip "项目描述: $description"
            tip " Web URL: $web_url"
            tip "HTTP URL: $http_url_to_repo"
            tip " SSH URL: $ssh_url_to_repo"
            tip "项目备份目录: $project_path_dir"

            mkdir -p "$project_path_dir"

            # 进入项目父目录
            cd "$project_path_dir"

            if [[ -d "${project_path}.git" ]]; then
                if [[ -n "${FORCE:-}" ]]; then
                    warn "项目已存在, 强制覆盖"
                    rm -rf "${project_path}.git"
                else
                    warn "项目已存在, 跳过备份"
                    echo ""
                    # 返回顶级目录
                    cd "$backup_path"
                    continue
                fi
            fi

            echo ""

            # 执行备份
            if [[ "$MODE" == "ssh" ]]; then
                git clone "$ssh_url_to_repo" --bare
            else
                http_url_repo="https://${USERNAME_TOKEN:-}@${http_url_to_repo#https://}"
                git clone "$http_url_repo" --bare
            fi
            echo "====================================================================="
            echo ""
            # 返回顶级目录
            cd "$backup_path"
            # echo "${project}" | jq '. | {id, name, path, path_with_namespace, description, web_url, http_url_to_repo, ssh_url_to_repo}'
            # break
        done    

        echo "${project_json}" | jq '[.[] | {
            id, 
            name, 
            path, 
            path_with_namespace, 
            description, 
            web_url, 
            http_url_to_repo, 
            ssh_url_to_repo
        }]' | tee "backup.json" > /dev/null 2>&1
    popd > /dev/null 2>&1

    echo ""
    warn "备份完成"
    warn "备份路径: $backup_path"
    warn "备份完成"
    echo ""
}

# 处理参数信息
judgment_parameters() {
    while [[ "$#" -gt '0' ]]; do
        case "${1,,}" in
            '-t' | '--token') 
            # TOKEN
                shift
                TOKEN="${1:?"错误: 令牌 (token) 不能为空."}"
                ;;

            '-u' | '--url')
            # URL
                shift
                URL="${1:?"错误: 自托管网址 (url) 不能为空."}"
                ;;

            '-b' | '--backup')
            # 执行备份
                BACKUP=1
                ;;

            '-s' | '--select') 
            # 选择
                shift
                SELECT="${1:?"错误: 选择类型 (select) 不能为空."}"
                ;;
            '-a' | '--action') 
            # 操作
                shift
                ACTION="${1:?"错误: 操作类型 (action) 不能为空."}"
                ;;
            '-m' | '--mode')
            # 模式
                shift
                MODE="${1:?"错误: 模式 (mode) 不能为空."}"
                ;;
            '-f' | '--force')
            # 强制覆盖
                FORCE=1
                ;;

            '-pa' | '--page') 
            # 页码
                shift
                PAGE="${1:?"错误: 页码 (page) 不能为空."}"
                ;;

            '-pp' | '--per_page') 
            # 每页数量
                shift
                PER_PAGE="${1:?"错误: 每页数量 (per_page) 不能为空."}"
                ;;

            '-h' | '--help')
                HELP=1
                ;;

            *)
                if [[ "$#" -gt '1' ]]; then
                    # 将变量赋值给变量名
                    if [[ "$1" == --* ]]; then
                        # 删除变量名前的破折号
                        var_name="${1#--}"
                        # 将变量名转换为大写（可选）
                        var_name="${var_name^^}"
                        # 赋值
                        eval "${var_name}=\"${2}\""
                        shift
                    fi
                else
                    echo "$0: 未知选项 -- $1" >&2
                    exit 1
                fi
                ;;
        esac
        shift
    done
}

# 显示帮助信息
show_top_help() {
    cat <<EOF
用法: $0 [options]

GitLab 账号源码仓库备份

-h, --help          打印帮助信息
-t, --token         私有令牌
-u, --url           自托管网址, 默认: https://gitlab.com
-b, --backup        执行备份
-m, --mode          模式,默认 https
    ssh             ssh 模式
    https           https 模式
-s, --select        选择区域
        group       团队
        project     项目
        user        用户
-a, --action        执行操作
EOF
    exit 0
}

# 显示帮助信息
show_help() {
    case "${SELECT:-}" in
        'gr' | 'group') 
            help_group
            ;;
        'pr' | 'project')
            help_project
            ;;

        'us' | 'user')
            help_user
            ;;

        *)
            show_top_help
            ;;
    esac
    exit 0
}

main() {
    judgment_parameters "$@"

    if [[ $# -eq 0 ]]; then
        HELP=1
    fi
    if [[ -n "${HELP:-}" ]]; then
        show_help
    fi

    if [[ -z "${TOKEN:-}" ]]; then
        TOKEN="${GITLAB_TOKEN:-}"
    fi

    if [[ -z "$TOKEN" ]]; then
        error_exit "缺失令牌"
    fi

    API_URL="${URL:-$DEFAULT_URL}${API_VERSION}"
    if ! is_url "$API_URL"; then
        error_exit "无效的URL. 如 https://gitlab.com"
    fi

    if [[ -n "${BACKUP:-}" ]]; then
        backup
        exit 0
    fi

    case "${SELECT:-}" in
        'gr' | 'group') 
            # 项目组
            group  
            ;;  

        'pr' | 'project')
            # 项目
            project
            ;;

        'us' | 'user')
            # 用户
            user
            ;;

        *)
            error_exit "无效的操作类型."
            ;;
    esac
}

main "$@"