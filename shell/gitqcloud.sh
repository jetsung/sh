#!/usr/bin/env bash

# 腾讯工峰 命令行工具 (未完成)
# 基于 https://code.tencent.com/help/api/prepare
# 包含：
##  项目组(group)
##  命名空间(namespace)
##  用户(user)
##  标签(labels)
##  Tag 相关（tag）
##  提交相关（commit）TODO
##  项目相关（projects）
##  复刻（TODO）
# 未包含：缺陷单(issue)
##  里程碑(milestone)
##  关注者（watcher）
##  库操作以及文件操作（repository）
##  项目分支管理（branch）
# 
# 作者: Jetsung Chan
#

set -euo pipefail
# set -eux

API_BASE="https://git.code.tencent.com"
API_URL="${API_BASE}/api/v3"

# 输出错误信息并退出
error_exit() {
    echo -e "\033[31merror: $1\033[0m" >&2
    exit 1
}

warn() {
    echo -e "\033[33m$1\033[0m"
}

# 通用请求函数
do_request() {
    local method="${METHOD:-GET}"
    local update_data="${UPDATE_DATA:-{}}"
    local headers=()

    if [ -n "$TOKEN" ]; then
        headers+=("-H" "PRIVATE-TOKEN: $TOKEN")
    else
        error_exit "TOKEN must be set."
    fi

    curl -s -X "$method" "$API_REQ" \
        "${headers[@]}" \
        -H "Content-Type: application/json" \
        -d "$update_data"
}

# 新建项目组
## name	string	项目组的名字
## path	string	项目组的路径
## description	string	关于这个项目组的描述
api_group_create() {
    API_REQ="${API_URL}/groups"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg name "${NAME:-$GPATH}" --arg path "$GPATH" --arg description "${DESCRIPTION:-}" '{name: $name, path: $path, description: $description}')

    do_request | jq -r '.'
}

# 编辑项目组
## id	integer	用户的项目组 ID 或者路径
## name	string	项目组的名字
## description	string	关于这个项目组的描述
api_group_update() {
    API_REQ="${API_URL}/groups/$ID"
    METHOD="PUT"

    UPDATE_DATA=$(jq -n --arg name "$NAME" --arg description "${DESCRIPTION:-}" '{name: $name, description: $description}')

    do_request | jq -r '.'
}

# 删除项目组
## id	integer	用户的项目组 ID 或者路径
api_group_delete() {
    API_REQ="${API_URL}/groups/$ID"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 获取项目组列表
## page	int	页码
## per_page	int	每页数量
api_group_list() {
    API_REQ="${API_URL}/groups/?search=${SEARCH:-}"
    METHOD="GET"
    UPDATE_DATA=$(jq -n --arg page "${PAGE:-1}" --arg per_page "${PER_PAGE:-20}" '{page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 获取项目组成员列表
## id	integer	项目组唯一标识或路径
## page	integer（可选）	分页 (默认:1)
## per_page	integer（可选）	默认页面大小 (默认 20，最大： 100)
api_group_members_list() {
    API_REQ="${API_URL}/groups/$ID/members"
    METHOD="GET"
    UPDATE_DATA=$(jq -n --arg page "${PAGE:-1}" --arg per_page "${PER_PAGE:-20}" '{page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 增加项目组成员
## id	integer	项目组的 ID
## user_id	integer	用户的 ID
## access_level	integer	用户的访问级别
api_group_members_add() {
    API_REQ="${API_URL}/groups/$ID/members"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg user_id "$USER_ID" --arg access_level "$ACCESS_LEVEL" '{user_id: $user_id, access_level: $access_level}')

    do_request | jq -r '.'
}

# 修改项目组成员
## id	integer	id = 项目组唯一标识或路径
## user_id	integer	项目组成员的 ID
## access_level	integer	项目访问级别
api_group_member_update() {
    API_REQ="${API_URL}/groups/$ID/members/$USER_ID"
    METHOD="PUT"

    UPDATE_DATA=$(jq -n --arg access_level "$ACCESS_LEVEL" '{access_level: $access_level}')

    do_request | jq -r '.'
}

# 移除一个项目组成员
## id	integer 项目组唯一标识或路径
## user_id	integer	项目组成员的 ID
api_group_member_delete() {
    API_REQ="${API_URL}/groups/$ID/members/$USER_ID"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 获取项目组的详细信息以及项目组下所有项目
## id	integer	项目组唯一标识或路径
api_group_projects() {
    API_REQ="${API_URL}/groups/$ID"
    METHOD="GET"

    do_request | jq -r '.'
}

# 获取命名空间列表
## page	integer （可选）	分页 (默认值:1)
## per_page	integer （可选）	默认页面大小 (默认值 20，最大值： 100)
api_namespaces_list() {
    API_REQ="${API_URL}/namespaces?search=${SEARCH:-}"
    METHOD="GET"
    UPDATE_DATA=$(jq -n --arg page "${PAGE:-1}" --arg per_page "${PER_PAGE:-20}" '{page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 获取用户信息列表
## page	integer（可选）	页数 (默认值:1)
## per_page	integer（可选）	默认页面大小 (默认值 20，最大值： 100)
api_users_list() {
    API_REQ="${API_URL}/users"
    METHOD="GET"
    UPDATE_DATA=$(jq -n --arg page "${PAGE:-1}" --arg per_page "${PER_PAGE:-20}" '{page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 获用户关注项目列表
api_user_watch() {
    API_REQ="${API_URL}/user/watched"
    METHOD="GET"

    do_request | jq -r '.'
}

# 获取单个用户信息
## id	integer 或 string	用户唯一标识或用户名称
api_users_info() {
    API_REQ="${API_URL}/users/$ID"
    METHOD="GET"

    do_request | jq -r '.'
}

# 当前认证用户
api_user_current() {
    API_REQ="${API_URL}/user"
    METHOD="GET"

    do_request | jq -r '.'
}   

# 给当前用户创建一个 SSH key
## title	string	SSH key 的标题
## key	string	SSH key 的内容
api_user_keys_add() {
    API_REQ="${API_URL}/user/keys"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg title "$TITLE" --arg key "$KEY" '{title: $title, key: $key}')

    do_request | jq -r '.'
}

# 获取当前用户的 SSH key
api_user_keys_list() {
    API_REQ="${API_URL}/user/keys"
    METHOD="GET"

    do_request | jq -r '.'
}

# 获取某个指定的 SSH key
## id	integer	SSH key 的 ID
api_user_keys_info() {
    API_REQ="${API_URL}/user/keys/$ID"
    METHOD="GET"

    do_request | jq -r '.'
}

# 删除当前用户的 SSH key
## id	integer	SSH key 的 ID
api_user_keys_delete() {
    API_REQ="${API_URL}/user/keys/$ID"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 添加邮箱
## email	string	邮箱地址
api_user_emails_add() {
    API_REQ="${API_URL}/user/emails"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg email "$EMAIL" '{email: $email}')

    do_request | jq -r '.'
}

# 通过邮箱获取用户信息
## email	string	邮箱地址
api_user_emails_user() {
    API_REQ="${API_URL}/user/email?email=$EMAIL"
    METHOD="GET"

    do_request | jq -r '.'
}

# 获取用户邮箱列表
api_user_emails_list() {
    API_REQ="${API_URL}/user/emails"
    METHOD="GET"

    do_request | jq -r '.'
}

# 获取邮箱信息
## id	integer	邮箱的 ID
api_user_emails_info() {
    API_REQ="${API_URL}/user/emails/$ID"
    METHOD="GET"

    do_request | jq -r '.'
}

# 删除当前用户的邮箱
## id	integer	邮箱的 ID
api_user_emails_delete() {
    API_REQ="${API_URL}/user/emails/$ID"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 新增标签
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## name	string	标签名
## color	string	标签颜色，举例：#428bca
api_projects_labels_add() {
    API_REQ="${API_URL}/projects/$ID/labels"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg name "$NAME" --arg color "$COLOR" '{name: $name, color: $color}') 

    do_request | jq -r '.'
}

# 修改标签
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## name	string	旧标签名
## new_name	string	新标签名
## color	string	标签颜色，举例：#428bca
api_projects_labels_update() {
    API_REQ="${API_URL}/projects/$ID/labels"
    METHOD="PUT"

    UPDATE_DATA=$(jq -n --arg name "$NAME" --arg new_name "$NEW_NAME" --arg color "${COLOR:-}" '{name: $name, new_name: $new_name, color: $color}')

    do_request | jq -r '.'
}

# 获取标签列表
## id	integer 或 string  项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## order_by	string（可选）	排序字段，允许按 name,created_at 排序（默认 name）
## sort	string（可选）	排序方式，允许 asc,desc（默认 asc）
## page	integer（可选）	分页（默认值：1）
## per_page	integer（可选）	默认页面大小（默认值：20，最大值：100）
api_projects_labels_list() {
    API_REQ="${API_URL}/projects/$ID/labels"
    METHOD="GET"
    UPDATE_DATA=$(jq -n --arg order_by "${ORDER_BY:-name}" --arg sort "${SORT:-asc}" --arg page "$PAGE" --arg per_page "$PER_PAGE" '{order_by: $order_by, sort: $sort, page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 删除标签
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## name	string	标签名
api_projects_labels_delete() {
    API_REQ="${API_URL}/projects/$ID/labels"
    METHOD="DELETE"

    UPDATE_DATA=$(jq -n --arg name "$NAME" '{name: $name}')

    do_request | jq -r '.'
}

# 获取标签列表
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## page	integer（可选）	分页（default：1）
## per_page	integer（可选）	默认页面大小（default：20，max：100）
api_tags_list() {
    API_REQ="${API_URL}/projects/$ID/repository/tags"
    METHOD="GET"

    UPDATE_DATA=$(jq -n --arg page "${PAGE:-1}" --arg per_page "${PER_PAGE:-20}" '{page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 获取指定 TAG
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## tag	string	tag 名
api_tags_info() {
    API_REQ="${API_URL}/projects/$ID/repository/tags/$NAME"
    METHOD="GET"

    do_request | jq -r '.'
}

# 新增 TAG
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## tag_name	string	tag 名
## ref	string	从 commit hash、存在的 branch 或 tag 创建 tag
## message	string（可选）	描述、注释
api_tags_create() {
    API_REQ="${API_URL}/projects/$ID/repository/tags"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg tag_name "$NAME" \
        --arg ref "$REF" \
        --arg message "${MESSAGE:-}" \
        '{tag_name: $tag_name, ref: $ref, message: $message}')

    do_request | jq -r '.'
}

# 删除 TAG
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
# tag	string	tag 名
api_tags_delete() {
    API_REQ="${API_URL}/projects/$ID/repository/tags/$NAME"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 获取项目成员列表
## page	integer	页数 (默认值:1)
## per_page	integer	每页列出成员数 (默认值 20)
## id	integer 或者 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## query	string (可选)	搜索成员的字符串
api_projects_members_list() {
    API_REQ="${API_URL}/projects/$ID/members"
    METHOD="GET"
    UPDATE_DATA=$(jq -n --arg page "${PAGE:-1}" \
        --arg per_page "${PER_PAGE:-20}" \
        --arg query "${QUERY:-}" \
        '{page: $page, per_page: $per_page, query: $query}')

    do_request | jq -r '.'
}

# 增加项目成员
## id	integer	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## user_id	integer	增加的用户的 ID
## access_level	integer	项目访问级别
### GUEST = 10
### FOLLOWER = 15
### REPORTER = 20
### DEVELOPER = 30
### MASTER = 40
### OWNER = 50
api_projects_members_add() {
    API_REQ="${API_URL}/projects/$ID/members"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg user_id "$USER_ID" --arg access_level "$ACCESS_LEVEL" '{user_id: $user_id, access_level: $access_level}')

    do_request | jq -r '.'
}

# 修改项目成员
## id	integer	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## user_id	integer	用户的 ID
## access_level	integer	项目访问级别
api_projects_members_update() {
    API_REQ="${API_URL}/projects/$ID/members/$USER_ID"
    METHOD="PUT"

    UPDATE_DATA=$(jq -n --arg access_level "$ACCESS_LEVEL" '{access_level: $access_level}')

    do_request | jq -r '.'
}

# 删除项目成员
## id	integer	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## user_id	integer	用户的 ID
api_projects_members_delete() {
    API_REQ="${API_URL}/projects/$ID/members/$USER_ID"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 获取项目内的某个指定成员信息
## id	integer	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## user_id	integer	成员的 ID
api_projects_members_info() {
   API_REQ="${API_URL}/projects/$ID/members/$USER_ID"
   METHOD="GET"

   do_request | jq -r '.' 
}

# 创建项目
## name	string	项目名
## path	string（可选）	项目版本库路径，默认：path = name
## fork_enabled	boolean（可选）	项目是否可以被fork，默认：false
## namespace_id	integer 或者 string（可选）	项目所属命名空间 ，默认用户的命名空间
## description	string（可选）	项目描述
## visibility_level	integer（可选）	项目可视范围，默认visibility_level = 0
api_projects_create() {
    API_REQ="${API_URL}/projects"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg name "$NAME" \
        --arg path "${GPATH:-}" \
        --arg fork_enabled "${FORK_ENABLED:-false}" \
        --arg namespace_id "${NAMESPACE_ID:-}" \
        --arg description "${DESCRIPTION:-}" \
        --arg visibility_level "${VISIBILITY_LEVEL:-0}" \
        '{name: $name, path: $path, fork_enabled: $fork_enabled, namespace_id: $namespace_id, description: $description, visibility_level: $visibility_level}')

    do_request | jq -r '.'
}

# 编辑项目
## id	integer	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## name	string（可选）	项目名
## description	string（可选）	项目描述
## default_branch	string（可选）	项目默认分支
## limit_file_size	float（可选）	文件大小限制，单位:MB
## limit_lfs_file_size	float（可选）	LFS 文件大小限制，单位:MB
## issues_enabled	boolean（可选）	缺陷配置
## merge_requests_enabled	boolean（可选）	合并请求配置
## wiki_enabled	boolean（可选）	维基配置
## review_enabled	boolean（可选）	评审配置
## fork_enabled	boolean（可选）	是否可以被fork，默认:false
## tag_name_regex	string（可选）	推送或创建 tag 规则
## tag_create_push_level	integer（可选）	推送或创建 tag 权限
## visibility_level	integer（可选）	项目可视范围
api_projects_update() {
    API_REQ="${API_URL}/projects/$ID"
    METHOD="PUT"

    UPDATE_DATA=$(jq -n --arg name "${NAME:-}" \
        --arg description "${DESCRIPTION:-}" \
        --arg default_branch "${DEFAULT_BRANCH:-}" \
        --arg limit_file_size "${LIMIT_FILE_SIZE:-}" \
        --arg limit_lfs_file_size "${LIMIT_LFS_FILE_SIZE:-}" \
        --arg issues_enabled "${ISSUES_ENABLED:-}" \
        --arg merge_requests_enabled "${MERGE_REQUESTS_ENABLED:-}" \
        --arg wiki_enabled "${WIKI_ENABLED:-}" \
        --arg review_enabled "${REVIEW_ENABLED:-}" \
        --arg fork_enabled "${FORK_ENABLED:-false}" \
        --arg tag_name_regex "${TAG_NAME_REGEX:-}" \
        --arg tag_create_push_level "${TAG_CREATE_PUSH_LEVEL:-}" \
        --arg visibility_level "${VISIBILITY_LEVEL:-0}" \
        '{name: $name, description: $description, default_branch: $default_branch, limit_file_size: $limit_file_size, limit_lfs_file_size: $limit_lfs_file_size, issues_enabled: $issues_enabled, merge_requests_enabled: $merge_requests_enabled, wiki_enabled: $wiki_enabled, review_enabled: $review_enabled, fork_enabled: $fork_enabled, tag_name_regex: $tag_name_regex, tag_create_push_level: $tag_create_push_level, visibility_level: $visibility_level}')

    do_request | jq -r '.'
}

# 获取用户授权的项目列表
## archived	boolean（可选）	归档状态，archived = true限制为查询归档项目，默认不区分归档状态
# 通过名称搜索项目
## with_archived	boolean（可选）	归档状态，with_archived = true限制为查询归档项目，默认不区分
## with_push	boolean（可选）	推送状态，with_push = true限制为查询推送过的项目，默认不区分
## abandoned	boolean（可选）	活跃状态，abandoned = true限制为查询最近半年更新过的项目，默认全部
## visibility_levels	string（可选）	项目可视范围，默认 visibility_levels = "0, 10, 20"
# 共用参数
## search	string （可选）	搜索条件，模糊匹配 path,name
## order_by	string （可选）	排序字段，允许按 id,name,path,created_at,updated_at,last_activity_at排序（默认created_at）
## sort	string （可选）	排序方式，允许asc,desc（默认 desc）
## page	integer（可选）	页数（默认值：1）
## per_page	integer（可选）	默认页面大小（默认值：20，最大值：100）
api_projects_list() {
    API_REQ="${API_URL}/projects"
    METHOD="GET"

    UPDATE_DATA=$(jq -n --arg archived "${ARCHIVED:-}" \
        --arg with_archived "${ARCHIVED:-}" \
        --arg with_push "${WITH_PUSH:-}" \
        --arg abandoned "${ABANDONED:-}" \
        --arg visibility_levels "${VISIBILITY_LEVEL:-}" \
        --arg search "${SEARCH:-}" \
        --arg order_by "${ORDER_BY:-}" \
        --arg sort "${SORT:-}" \
        --arg page "${PAGE:-1}" \
        --arg per_page "${PER_PAGE:-20}" \
        '{archived: $archived, with_archived: $with_archived, with_push: $with_push, abandoned: $abandoned, visibility_levels: $visibility_levels, search: $search, order_by: $order_by, sort: $sort, page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 获取用户拥有的项目列表
## search	string（可选）	搜索条件，模糊匹配path, name
## archived	boolean（可选）	归档状态，archived = true限制为查询归档项目，默认不区分归档状态
## order_by	string（可选）	排序字段，允许按 id,name,path,created_at,updated_at,last_activity_at排序（默认created_at）
## sort	string（可选）	排序方式，允许 asc or desc（默认 desc）
## page	integer（可选）	页数（默认值：1）
## per_page	integer（可选）	默认页面大小（默认值：20，最大值：100）
api_projects_owned_list() {
    API_REQ="${API_URL}/projects/owned"
    METHOD="GET"

    UPDATE_DATA=$(jq -n --arg search "${SEARCH:-}" \
        --arg archived "${ARCHIVED:-}" \
        --arg order_by "${ORDER_BY:-}" \
        --arg sort "${SORT:-}" \
        --arg page "${PAGE:-1}" \
        --arg per_page "${PER_PAGE:-20}" \
        '{search: $search, archived: $archived, order_by: $order_by, sort: $sort, page: $page, per_page: $per_page}')

    do_request | jq -r '.'
}

# 删除项目
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
api_projects_delete() {
    API_REQ="${API_URL}/projects/$ID"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 获取项目详细信息
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
api_projects_info() {
    API_REQ="${API_URL}/projects/$ID"
    METHOD="GET"

    do_request | jq -r '.'
}

# 与组共享项目
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## group_id	integer	要与之共享的组的id
## group_access	integer	授予组的权限级别
api_projects_share_add() {
    API_REQ="${API_URL}/projects/$ID/share"
    METHOD="POST"

    UPDATE_DATA=$(jq -n --arg group_id "$GROUP_ID" --arg group_access "${GROUP_ACCESS:-0}" '{group_id: $group_id, group_access: $group_access}')

    do_request | jq -r '.'
}

# 获取项目的共享组列表
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
api_projects_share_list() {
    API_REQ="${API_URL}/projects/$ID/shares"
    METHOD="GET"

    do_request | jq -r '.'
}

# 删除组中共享项目链接
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## group_id	integer	要与之共享的组的id
api_projects_share_delete() {
    API_REQ="${API_URL}/projects/$ID/share/$GROUP_ID?group_id=$GROUP_ID"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 查询项目的事件列表
## id	integer or string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## user_id_or_name	integer 或 string（可选）	用户的 id 或用户名
## page	integer	页数（默认值：1）
## per_page	integer	默认页面大小（默认值： 20，最大值： 100）
api_projects_events_list() {
    API_REQ="${API_URL}/projects/$ID/events"
    METHOD="GET"

    UPDATE_DATA=$(jq -n --arg user_id_or_name "${USER_ID:-}" \
        --arg page "${PAGE:-1}" \
        --arg per_page "${PER_PAGE:-20}" \
        '{user_id_or_name: $user_id_or_name, page: $page, per_page: $per_page}')

    do_request | jq -r '.'    
}

# 对指定项目标星（官方功能有问题）
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
api_projects_star_add() {
    API_REQ="${API_URL}/projects/$ID/star"
    METHOD="PUT"

    do_request | jq -r '.'
}

# 取消对指定项目标星
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
api_projects_star_delete() {
    API_REQ="${API_URL}/projects/$ID/star"
    METHOD="DELETE"

    do_request | jq -r '.'
}

# 查看对指定项目是否标星
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
api_projects_star_info() {
    API_REQ="${API_URL}/projects/$ID/star"
    METHOD="GET"

    do_request | jq -r '.'
}

# 获取标星项目列表
## id	integer 或 string	项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
## page	integer（可选）	页数（默认值：1）
## per_page	integer（可选）	默认页面大小（默认值： 20，最大值： 100）
api_projects_star_list() {
    API_REQ="${API_URL}/projects/$ID/stars"
    METHOD="GET"

    UPDATE_DATA=$(jq -n --arg page "${PAGE:-1}" --arg per_page "${PER_PAGE:-20}" '{page: $page, per_page: $per_page}')

    do_request | jq -r '.'
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

            '-id' | '--id') 
                shift
                ID="${1:?"错误: ID (id) 不能为空."}"
                ;;
            '-na' | '--name') 
            # 名字
                shift
                NAME="${1:?"错误: 名字 (name) 不能为空."}"
                ;;
            '-ph' | '--path') 
            # 路径
                shift
                GPATH="${1:?"错误: 路径 (path) 不能为空."}"
                ;;
            '-de' | '--description') 
            # 描述
                shift
                DESCRIPTION="${1:?"错误: 描述 (description) 不能为空."}"
                ;;
            '-se' | '--search') 
            # 搜索
                shift
                SEARCH="${1:?"错误: 搜索 (search) 不能为空."}"
                ;;
            '-ui' | '--user_id') 
            # USER_ID
                shift
                USER_ID="${1:?"错误: USER_ID (user_id) 不能为空."}"
                ;;
            '-al' | '--access_level') 
            # 访问级别
                shift
                ACCESS_LEVEL="${1:?"错误: 访问级别 (access_level) 不能为空."}"
                ;;
            '-ti' | '--title') 
            # SSH KEY 的标题
                shift
                TITLE="${1:?"错误: 标题 (title) 不能为空."}"
                ;;
            '-ke' | '--key') 
            # SSH KEY 的内容
                shift
                KEY="${1:?"错误: SSH KEY 的内容 (key) 不能为空."}"
                ;;
            '-em' | '--email') 
            # 邮箱地址
                shift
                EMAIL="${1:?"错误: 邮箱地址 (email) 不能为空."}"
                ;;
            '-co' | '--color') 
            # 标签颜色
                shift
                COLOR="${1:?"错误: 标签颜色 (color) 不能为空."}"
                ;;
            '-nn' | '--new_name') 
            # 新标签名
                shift
                NEW_NAME="${1:?"错误: 新标签名 (new_name) 不能为空."}"
                ;;
            '-ob' | '--order_by') 
            # 排序字段
                shift
                ORDER_BY="${1:?"错误: 排序字段 (order_by) 不能为空."}"
                ;;
            '-so' | '--sort') 
            # 排序方式
                shift
                SORT="${1:?"错误: 排序方式 (sort) 不能为空."}"
                ;;
            '-re' | '--ref') 
            # 源
                shift
                REF="${1:?"错误: 源 (ref) 不能为空."}"
                ;;
            '-me' | '--message') 
            # 消息
                shift
                MESSAGE="${1:?"错误: 消息 (message) 不能为空."}"                
                ;;
            '-qu' | '--query') 
            # 查询
                shift
                QUERY="${1:?"错误: 查询 (query) 不能为空."}"
                ;;
            '-fe' | '--fork_enabled') 
            # 是否可以被 fork
                shift
                FORK_ENABLED="${1:?"错误: 是否可以被 fork (fork_enabled) 不能为空."}"
                ;;
            '-nd' | '--namespace_id') 
            # 命名空间 ID
                shift
                NAMESPACE_ID="${1:?"错误: 命名空间 ID (namespace_id) 不能为空."}"
                ;;
            '-vl' | '--visibility_level') 
            # 可见性级别
                shift
                VISIBILITY_LEVEL="${1:?"错误: 可见性级别 (visibility_level) 不能为空."}"
                ;;
            '-db' | '--default_branch') 
            # 默认分支
                shift
                DEFAULT_BRANCH="${1:?"错误: 默认分支 (default_branch) 不能为空."}"
                ;;
            '-lf' | '--limit_file_size') 
            # 文件大小限制 MB
                shift
                LIMIT_FILE_SIZE="${1:?"错误: 文件大小限制 MB (limit_file_size) 不能为空."}"
                ;;
            '-ll' | '--limit_lfs_file_size') 
            # LFS 文件大小限制 MB
                shift
                LIMIT_LFS_FILE_SIZE="${1:?"错误: LFS 文件大小限制 MB (limit_lfs_file_size) 不能为空."}"
                ;;
            '-ie' | '--issues_enabled') 
            # 	缺陷配置
                shift
                ISSUES_ENABLED="${1:?"错误: 缺陷配置 (issues_enabled) 不能为空."}"
                ;;
            '-mr' | '--merge_requests_enabled') 
            # 合并请求配置
                shift
                MERGE_REQUESTS_ENABLED="${1:?"错误: 合并请求配置 (merge_requests_enabled) merge_requests_enabled 不能为空."}"
                ;;
            '-we' | '--wiki_enabled') 
            # 维基配置
                shift
                WIKI_ENABLED="${1:?"错误: 维基配置 (wiki_enabled) 不能为空."}"
                ;;
            '-rn' | '--review_enabled') 
            # 评审配置
                shift
                REVIEW_ENABLED="${1:?"错误: 评审配置 (review_enabled) 不能为空."}"
                ;;
            '-tn' | '--tag_name_regex') 
            # 推送或创建 TAG 规则
                shift
                TAG_NAME_REGEX="${1:?"错误: 推送或创建 TAG 规则 (tag_name_regex) 不能为空."}"
                ;;
            '-tc' | '--tag_create_push_level') 
            # 推送或创建 TAG 权限
                shift
                TAG_CREATE_PUSH_LEVEL="${1:?"错误: 推送或创建 TAG 权限 (tag_create_push_level) 不能为空."}"
                ;;
            '-ar' | '--archived') 
            # 归档状态
                shift
                ARCHIVED="${1:?"错误: 归档状态 (archived) 不能为空."}"
                ;;
            'wp' | '--with_push')
            # 推送状态
                shift
                WITH_PUSH="${1:?"错误: 推送状态 (with_push) 不能为空."}"
                ;;
            '-ab' | '--abandoned')
            # 活跃状态
                shift
                ABANDONED="${1:?"错误: 活跃状态 (abandoned) 不能为空."}"
                ;;
            '-gd' | '--group_id') 
            # 共享组 ID
                shift
                GROUP_ID="${1:?"错误: 共享组 ID (group_id) 不能为空."}"
                ;;
            '-ga' | '--group_access') 
            # 共享组权限              
                shift
                GROUP_ACCESS="${1:?"错误: 共享组权限 (group_access) 不能为空."}"
                ;;
            '-h' | '--help')
                HELP=1
                ;;
            *)
                echo "$0: 未知选项 -- $1" >&2
                exit 1
                ;;
        esac
        shift
    done
}

help_group() {
    case "${ACTION:-}" in
        'cr' | 'create')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "cr")|$(warn "create")] [options]
    $(warn "新建项目组")

    -h,  --help                       打印帮助信息
    -pa, --path	             str      项目组的路径
    -na, --name	             str      可选,项目组的名字
    -de, --description	     str      可选,项目组的描述
EOF
        ;;  

        'up' | 'update')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "up")|$(warn "update")] [options]
    $(warn "编辑项目组")

    -h,  --help                       打印帮助信息
    -id, --id                int      用户的项目组 ID 或者路径
    -na, --name	             str      项目组的名字
    -de, --description	     str      可选,项目组的描述
EOF
        ;;    

        'de' | 'delete')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "de")|$(warn "delete")] [options]
    $(warn "删除项目组")

    -h,  --help                       打印帮助信息
    -id, --id                int      用户的项目组 ID 或者路径
EOF
        ;;               

        'li' | 'list')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "li")|$(warn "list")] [options]
    $(warn "获取命名空间列表")

    -h,  --help                       打印帮助信息
    -se, --search            str      可选,搜索条件，用户名称或者路径的命名空间
    -pa, --page              int      可选,页数（默认值：1）
    -pp, --per_page          int      可选,默认页面大小（默认值：20，最大值：100）  
EOF
        ;;      

        'ml' | 'members_list')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "ml")|$(warn "members_list")] [options]
    $(warn "获取项目组成员列表")

    -h,  --help                       打印帮助信息
    -id, --id                int      用户的项目组 ID 或者路径
    -pa, --page              int      可选,页数（默认值：1）
    -pp, --per_page          int      可选,默认页面大小（默认值：20，最大值：100）  
EOF
        ;;               

        'ma' | 'member_add')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "ma")|$(warn "member_add")] [options]
    $(warn "增加项目组成员")

    -h,  --help                       打印帮助信息
    -id, --id                int      项目组 ID 或者路径
    -ui, user_id             int      用户的 ID
    -al, access_level        int      用户的访问级别
                                        GUEST     = 10
                                        REPORTER  = 20
                                        FOLLOWER  = 25
                                        DEVELOPER = 30
                                        MASTER    = 40
                                        OWNER     = 50
EOF
        ;; 


        'mu' | 'member_update')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "mu")|$(warn "member_update")] [options]
    $(warn "修改项目组成员")

    -h,  --help                       打印帮助信息
    -id, --id                int      项目组 ID 或者路径
    -ui, user_id             int      用户的 ID
    -al, access_level        int      用户的访问级别
                                        GUEST     = 10
                                        REPORTER  = 20
                                        FOLLOWER  = 25
                                        DEVELOPER = 30
                                        MASTER    = 40
                                        OWNER     = 50
EOF
        ;;         

        'md' | 'member_delete')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "md")|$(warn "member_delete")] [options]
    $(warn "修改项目组成员")

    -h,  --help                       打印帮助信息
    -id, --id                int      项目组 ID 或者路径
    -ui, user_id             int      用户的 ID
EOF
        ;;  

        'pr' | 'projects')
            cat <<EOF
用法: $0 -s $(warn "group") --action [$(warn "pr")|$(warn "projects")] [options]
    $(warn "获取项目组的详细信息以及项目组下所有项目")

    -h,  --help                       打印帮助信息
    -id, --id                int      项目组 ID 或者路径
    -ui, user_id             int      用户的 ID
EOF
        ;;  

        *)
            cat <<EOF
用法: $0 -s $(warn "group") --action [options]

-h, --help                 打印帮助信息
-a, --action               指定操作类型
        cr create          新建项目组
        up update          编辑项目组
        de delete          删除项目组
        li list            获取项目组列表
        ml members_list    获取项目组成员列表
        ma member_add      增加项目组成员
        mu member_update   修改项目组成员
        md member_delete   移除一个项目组成员
        pr projects        获取项目组的详细信息以及项目组下所有项目        
EOF
            ;;    
    esac

    exit 0
}

group() {
    case "${ACTION:-}" in
        'cr' | 'create') 
            # 创建项目组
            api_group_create
            ;;
        'up' | 'update') 
            # 编辑项目组
            api_group_update
            ;;
        'de' | 'delete') 
            # 删除项目组
            api_group_delete
            ;;
        'li' | 'list') 
            # 获取项目组列表
            api_group_list
            ;;
        'ml' | 'members_list') 
            # 获取项目组成员列表
            api_group_members_list
            ;;
        'ma' | 'member_add') 
            # 增加项目组成员
            api_group_members_add
            ;;
        'mu' | 'member_update') 
            # 修改项目组成员
            api_group_member_update
            ;;
        'md' | 'member_delete') 
            # 移除一个项目组成员
            api_group_member_delete
            ;;
        'pr' | 'projects') 
            # 获取项目组的详细信息以及项目组下所有项目
            api_group_projects
            ;;
        *)
            error_exit "无效的操作类型."
            ;;
    esac
}

help_namespace() {
    case "${ACTION:-}" in
        'li' | 'list')
            cat <<EOF
用法: $0 -s $(warn "namespace") --action [$(warn "li")|$(warn "list")] [options]
    $(warn "获取命名空间列表")

    -h,  --help                       打印帮助信息
    -se, --search            str      可选,搜索条件，用户名称或者路径的命名空间
    -pa, --page              int      可选,页数（默认值：1）
    -pp, --per_page          int      可选,默认页面大小（默认值：20，最大值：100）  
EOF
        ;;  

        *)
            cat <<EOF
用法: $0 -s namespace --action [options]

-h, --help                 打印帮助信息
-a, --action               指定操作类型
        li list            获取命名空间列表
EOF
            ;;    
    esac

    exit 0
}

namespace() {
    case "${ACTION:-}" in
        'li' | 'list') 
            # 获取命名空间列表
            api_namespaces_list
            ;;
        *)
            api_namespaces_list
            ;;
    esac
}

help_user() {
    case "${ACTION:-}" in
        'li' | 'list')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "li")|$(warn "list")] [options]
    $(warn "获取用户信息列表")

    -h,  --help                       打印帮助信息
    -pa, --page              int      可选,页数（默认值：1）
    -pp, --per_page          int      可选,默认页面大小（默认值：20，最大值：100）  
EOF
            ;;  

        'wa' | 'watch')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "wa")|$(warn "watch")] [options]
    $(warn "获用户关注项目列表")

    -h,  --help                       打印帮助信息
EOF
            ;;  

        'sp' | 'specify')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "sp")|$(warn "specify")] [options]
    $(warn "获取单个用户信息")

    -h,  --help                       打印帮助信息
    -id, --id                int/str  用户唯一标识或用户名称
EOF
            ;;    

        'cu' | 'current')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "cu")|$(warn "current")] [options]
    $(warn "当前认证用户")

    -h,  --help                       打印帮助信息
EOF
            ;;                

        'ka' | 'key_add')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "ka")|$(warn "key_add")] [options]
    $(warn "给当前用户创建一个 SSH KEY")

    -h,  --help                       打印帮助信息
    -ti, --title             str      SSH key 的标题
    -ke, --key               str      SSH key 的内容    
EOF
            ;;

        'kd' | 'key_delete')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "kd")|$(warn "key_delete")] [options]
    $(warn "删除某个指定的 SSH KEY")

    -h,  --help                       打印帮助信息
    -id, --id                int/str  用户唯一标识或用户名称
EOF
            ;;   

        'kl' | 'key_list')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "kl")|$(warn "key_list")] [options]
    $(warn "获取当前用户的 SSH KEY")

    -h,  --help                       打印帮助信息
EOF
            ;;

        'ea' | 'email_add')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "ea")|$(warn "email_add")] [options]
    $(warn "添加邮箱")

    -h,  --help                       打印帮助信息
    -ea, --email             str      邮箱地址
EOF
            ;;   

        'ed' | 'email_delete')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "ed")|$(warn "email_delete")] [options]
    $(warn "删除某个指定的邮箱")

    -h,  --help                       打印帮助信息
    -id, --id                int      用户唯一标识或用户名称
EOF
            ;;   

        'el' | 'email_list')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "el")|$(warn "email_list")] [options]
    $(warn "获取用户邮箱列表")

    -h,  --help                       打印帮助信息
EOF
            ;;   

        'ei' | 'email_info')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "ei")|$(warn "email_info")] [options]
    $(warn "获取邮箱信息")

    -h,  --help                       打印帮助信息
    -id, --id                int      邮箱的 ID
EOF
            ;;   

        'eu' | 'email_user')
            cat <<EOF
用法: $0 -s $(warn "user") --action [$(warn "eu")|$(warn "email_user")] [options]
    $(warn "通过邮箱获取用户信息")

    -h,  --help                       打印帮助信息
    -em, --email                 str  邮箱地址
EOF
            ;;                                                                 

        *)
            cat <<EOF
用法: $0 -s $(warn "user") --action [options]

-h, --help                 打印帮助信息
-a, --action               指定操作类型
        li list            获取用户信息列表
        wa watch           获用户关注项目列表
        sp specify         获取单个用户信息
        cu current         当前认证用户
        ka key_add         给当前用户创建一个 SSH KEY
        kd key_delete      删除某个指定的 SSH KEY
        kl key_list        获取当前用户的 SSH KEY
        ki key_info        获取某个指定的 SSH KEY
        ea email_add       添加邮箱
        ed email_delete    删除某个指定的邮箱
        el email_list      获取用户邮箱列表
        ei email_info      获取邮箱信息
        eu email_user      通过邮箱获取用户信息        
EOF
            ;;    
    esac

    exit 0
}


user() {
    case "${ACTION:-}" in
        'li' | 'list') 
            # 获取用户列表
            api_users_list
            ;;
        'wa' | 'watch') 
            # 获取用户关注项目列表
            api_user_watch
            ;;
        'sp' | 'specify') 
            # 获取单个用户信息
            api_users_info
            ;;
        'cu' | 'current') 
            # 当前认证用户
            api_user_current
            ;;
        'ka' | 'key_add') 
            # 给当前用户创建一个 SSH KEY
            api_user_keys_add
            ;;
        'kd' | 'key_delete') 
            # 删除某个指定的 SSH KEY
            api_user_keys_delete
            ;;
        'kl' | 'key_list')
            # 获取当前用户的 SSH KEY
            api_user_keys_list
            ;;
        'ki' | 'key_info')
            # 获取某个指定的 SSH KEY
            api_user_keys_info
            ;;
        'ea' | 'email_add')
            # 添加邮箱
            api_user_emails_add
            ;;
        'ed' | 'email_delete')
            # 删除某个指定的邮箱
            api_user_emails_delete
            ;;
        'el' | 'email_list')
            # 获取用户邮箱列表
            api_user_emails_list
            ;;
        'ei' | 'email_info')
            # 获取邮箱信息
            api_user_emails_info
            ;;
        'eu' | 'email_user')
            # 通过邮箱获取用户信息
            api_user_emails_user
            ;;     
        *)
            error_exit "无效的操作类型."
            ;;
    esac
}

label() {
    case "${ACTION:-}" in
        'ad' | 'add') 
            # 新增标签
            api_projects_labels_add
            ;;
        'up' | 'update')
            # 修改标签
            api_projects_labels_update
            ;;
        'de' | 'delete')
            # 删除标签
            api_projects_labels_delete
            ;;
        'li' | 'list')
            # 获取标签列表
            api_projects_labels_list
            ;;
        *)
            error_exit "无效的操作类型."
            ;;
    esac
}

help_tag() {
    case "${ACTION:-}" in
        'ad' | 'add')
            cat <<EOF
用法: $0 -s $(warn "tag") --action [$(warn "ad")|$(warn "add")] [options]
    $(warn "新增 TAG")

    -h,  --help                       打印帮助信息
    -id, --id                int/str  项目唯一标识或 NAMESPACE_PATH/PROJECT_PATH
    -tn, --tag_name          str      TAG 名
    -re, --ref               str      从 commit hash、branch 或 tag 创建 tag
    -me, --message           str      可选,描述、注释
EOF
        ;;  

        'sp' | 'specify')
            cat <<EOF
用法: $0 -s $(warn "tag") --action [$(warn "sp")|$(warn "specify")] [options]
    $(warn "获取指定 TAG")

    -h,  --help                       打印帮助信息
    -id, --id                int/str  项目唯一标识或 NAMESPACE_PATH/PROJECT_PATH
    -tn, --tag_name          str      TAG 名
EOF
        ;;  

        'de' | 'delete')
            cat <<EOF
用法: $0 -s $(warn "tag") --action [$(warn "de")|$(warn "delete")] [options]
    $(warn "删除 TAG")

    -h,  --help                       打印帮助信息
    -id, --id                int/str  项目唯一标识或 NAMESPACE_PATH/PROJECT_PATH
    -tn, --tag_name          str      TAG 名
EOF
        ;;  

        'li' | 'list')
            cat <<EOF
用法: $0 -s $(warn "tag") --action [$(warn "li")|$(warn "list")] [options]
    $(warn "获取 TAG 列表 ")

    -h,  --help                       打印帮助信息
    -id, --id                int/str  项目唯一标识或 NAMESPACE_PATH/PROJECT_PATH
    -pa, --page              int      可选,页数（默认值：1）
    -pp, --per_page          int      可选,默认页面大小（默认值：20，最大值：100）  
EOF
        ;;  

        *)
            cat <<EOF
用法: $0 -s tag --action [options]

-h, --help                 打印帮助信息
-a, --action               指定操作类型
        ad add             新增 TAG
        sp specify         获取指定 TAG
        de delete          删除 TAG
        li list            获取 TAG 列表        
EOF
            ;;    
    esac

    exit 0
}

tag() {
    case "${ACTION:-}" in
        'ad' | 'add') 
            # 新增 TAG
            api_tags_create
            ;;
        'sp' | 'specify')
            # 获取指定 TAG
            api_tags_info
            ;;
        'de' | 'delete')
            # 删除 TAG
            api_tags_delete
            ;;
        'li' | 'list')
            # 获取 TAG 列表
            api_tags_list
            ;;
        *)
            error_exit "无效的操作类型."
            ;;
    esac
}

commit() {
    echo "todo"
}

help_project() {
    case "${ACTION:-}" in
        'cr' | 'create')
            cat <<EOF
用法: $0 -s $(warn "project") --action [$(warn "cr")|$(warn "create")] [options]
    $(warn "创建项目")

    -h,  --help                       打印帮助信息
    -na, --name	             str      项目名
    -ph, --path	             str      可选,项目版本库路径，默认：path = name
    -fn, --fork_enabled	     bool     可选,项目是否可以被 fork，默认：false
    -ni, --namespace_id	     int/str  可选,项目所属命名空间，默认用户的命名空间
    -de, --description	     str      可选,项目描述
    -vl, --visibility_level  int      可选,项目可视范围，默认 0

EOF
        ;;

        'up' | 'update')
            cat <<EOF
用法: $0 -s $(warn "project") --action [$(warn "up")|$(warn "update")] [options]
    $(warn "编辑项目")

    -h,  --help                       打印帮助信息
    -id, --id	             int      项目唯一标识或NAMESPACE_PATH/PROJECT_PATH
    -na, --name	             str      可选,项目名
    -de, --description	     str      可选,项目描述
    -db, --default_branch    str      可选,项目默认分支
    -lf, --limit_file_size   num      文件大小限制，单位：MB
    -ll, --limit_lfs_file_size	num   可选,LFS 文件大小限制，单位：MB
    -ie, issues_enabled	        bool  可选,缺陷配置
    -mr, merge_requests_enabled	bool  可选,合并请求配置
    -we, wiki_enabled	     bool     可选,维基配置
    -rn, review_enabled	     bool     可选,评审配置
    -fe, fork_enabled	     bool     可选,是否可以被fork，默认：false
    -tn, tag_name_regex	     str      可选,推送或创建 tag 规则
    -tc, tag_create_push_level	int   可选,推送或创建 tag 权限
    -vl, visibility_level    int      可选,项目可视范围

EOF
        ;;  

        'de' | 'delete')
            cat <<EOF
用法: $0 -s $(warn "project") --action [$(warn "de")|$(warn "delete")] [options]
    $(warn "删除项目")

    -h,  --help                       打印帮助信息
    -id, --id	             int      项目唯一标识或NAMESPACE_PATH/PROJECT_PATH     
EOF
        ;;  

        'li' | 'list')
            cat <<EOF
用法: $0 -s $(warn "project") --action [$(warn "li")|$(warn "list")] [options]
    $(warn "获取项目列表")

    -h,  --help                       打印帮助信息
    ...TODO...
    -ar, --archived          bool     可选,归档状态，true 限制为查询归档项目，默认不区分
    -wp, --with_push         bool     可选,推送状态，true 限制为查询推送过的项目，默认不区分
    -ab, --abandoned	     bool     可选,活跃状态，true 限制为查询最近半年更新过的项目，默认全部
    -vl, --visibility_level  str      可选,项目可视范围，默认 "0, 10, 20"
    -se, --search            str      可选,搜索条件，模糊匹配 path,name
    -ob, --order_by          str      可选,排序字段，允许按 id,name,path,created_at,updated_at,last_activity_at排序（默认created_at）
    -so, --sort              str      可选,排序方式，允许asc,desc（默认 desc）
    -pa, --page              int      可选,页数（默认值：1）
    -pp, --per_page          int      可选,默认页面大小（默认值：20，最大值：100）  
    ...TODO...
EOF
        ;;  

        *)
            cat <<EOF
用法: $0 -s project --action [options]

-h, --help                 打印帮助信息
-a, --action               指定操作类型
        ...TODO...
        cr create          创建项目
        up update          编辑项目
        de delete          删除项目
        li list            获取项目列表
        ow owned           获取用户授权的项目列表
        sp specify         获取项目详细信息
        sa share           与组共享项目
        sl share_list      获取项目的共享组列表
        sd share_delete    删除组中共享项目链接
EOF
            ;;    
    esac

    exit 0
}

project() {
    case "${ACTION:-}" in
        'ma' | 'member_add')
            # 增加项目成员
            api_projects_members_add
            ;;
        'mu' | 'member_update')
            # 修改项目成员
            api_projects_members_update
            ;;
        'md' | 'member_delete')
            # 删除项目成员
            api_projects_members_delete
            ;;
        'ml' | 'members_list')
            # 获取项目成员列表
            api_projects_members_list
            ;;
        'mi' | 'members_info')
            # 获取项目内的某个指定成员信息
            api_projects_members_info
            ;;
        'cr' | 'create') 
            # 创建项目
            api_projects_create
            ;;
        'up' | 'update') 
            # 更新项目
            api_projects_update
            ;;
        'de' | 'delete') 
            # 删除项目
            api_projects_delete
            ;;
        'li' | 'list') 
            # 获取项目列表
            api_projects_list
            ;;
        'ow' | 'owned') 
            # 获取用户授权的项目列表
            api_projects_owned_list
            ;;
        'sp' | 'specify') 
            # 获取项目详细信息
            api_projects_info
            ;;
        'sa' | 'share_add')
            # 与组共享项目
            api_projects_share_add
            ;;
        'sl' | 'share_list')
            # 获取项目的共享组列表
            api_projects_share_list
            ;;
        'sd' | 'share_delete')
            # 删除组中共享项目链接
            api_projects_share_delete
            ;;
        'el' | 'event_list')
            # 获取项目的事件列表
            api_projects_events_list
            ;;
        'xa' | 'star_add')
            # 对指定项目标星
            api_projects_star_add
            ;;
        'xd' | 'star_delete')
            # 取消对指定项目标星
            api_projects_star_delete
            ;;
        'xi'| 'star_info')
            # 查看对指定项目是否标星
            api_projects_star_info
            ;;
        'xl' | 'star_list')
            # 获取标星项目列表
            api_projects_star_list
            ;;
        *)
            error_exit "无效的操作类型."
            ;;
    esac
}

# 显示帮助信息
show_top_help() {
    cat <<EOF
用法: $0 --select [SELECT] --action [ACTION] [options]

TencentGit CLI

-h, --help          打印帮助信息
-t, --token         私有令牌
-s, --select        选择类型
        gr,group       项目组
        ns,namespace   命名空间
        us,user        用户
        la,label       标签
        ta,tag         TAG
-a, --action        指定操作类型     

EOF
    exit 0
}

# 显示帮助信息
show_help() {
    case "${SELECT:-}" in
        'gr' | 'group') 
            help_group
            ;;
        'ns' | 'namespace') 
            help_namespace
            ;;
        'us' | 'user') 
            help_user
            ;;
        'la' | 'label') 
            cat <<EOF
用法: $0 -s label [options]

-h, --help             打印帮助信息
-a, --action           指定操作类型
    ad add             新增标签
    up update          修改标签
    de delete          删除标签
    li list            获取标签列表

EOF
            ;;
        'ta' | 'tag') 
            help_tag
            ;;
        'co' | 'commit')
            cat <<EOF
用法: $0 -s commit [options]

-h, --help             打印帮助信息
-a, --action           指定操作类型
    ...TODO...
EOF
            ;;
        'pr' | 'project')
            help_project
            ;;
        *)
            show_top_help
            ;;
    esac
    exit 0
}

main() {
    judgment_parameters "$@"

    if [ -n "${HELP:-}" ]; then
        show_help
    fi

    if [ -z "${TOKEN:-}" ]; then
        TOKEN="${TENCENT_TOKEN:-}"
    fi

    if [ -z "$TOKEN" ]; then
        error_exit "缺失令牌"
    fi

    case "${SELECT:-}" in
        'gr' | 'group') 
            # 项目组
            group
            ;;
        'ns' | 'namespace') 
            # 命名空间
            namespace
            ;;
        'us' | 'user') 
            # 用户
            user
            ;;
        'la' | 'label') 
            # 标签
            label
            ;;
        'ta' | 'tag') 
            # Tag
            tag
            ;;
        'co' | 'commit')
            # 提交
            commit
            ;;
        'pr' | 'project')
            # 项目
            project
            ;;
        *)
            error_exit "无效的操作类型."
            ;;
    esac
}

main "$@"