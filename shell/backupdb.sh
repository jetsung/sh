#!/usr/bin/env bash
#============================================================
# File: backupdb.sh
# Description: 备份 MySQL 和 PostgreSQL 数据库的脚本
#              支持 Docker 容器、全量备份、压缩、预执行脚本
# URL: https://fx4.cn/backupdb
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.0
# CreatedAt: 2026-06-24
# UpdatedAt: 2026-06-25
#============================================================

if [[ -n "$DEBUG" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 脚本路径
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_PATH}/.env"
CRON_TAG="# backupdb-managed"

LOG_FILE="${BACKUPDB_LOG_FILE:-}"
LOG_LEVEL="${BACKUPDB_LOG_LEVEL:-}"

readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

_get_log_level_value() {
    case "$1" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

log() {
    local level="${1:-INFO}"
    shift
    local message="$*"
    
    local current_level_value
    local message_level_value
    current_level_value=$(_get_log_level_value "$LOG_LEVEL")
    message_level_value=$(_get_log_level_value "$level")
    
    if [[ $message_level_value -lt $current_level_value ]]; then
        return
    fi
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local formatted_message="[$timestamp] [$level] $message"
    
    echo "$formatted_message" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted_message" >> "$LOG_FILE"
    fi
}

# 执行前置/后置脚本
do_exec() {
    local exec_file="${SCRIPT_PATH}/exec_${1}.sh"
    if [[ -f "$exec_file" ]]; then
        if ! "$exec_file" "$2"; then
            log ERROR "错误：执行 $exec_file 失败"
            exit 1
        fi
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Database backup tool for MySQL and PostgreSQL.

Commands:
    backup          Backup database (default)
    init            Initialize .env configuration file
    cron add        Add scheduled backup task
    cron del        Remove scheduled backup task
    cron list       List scheduled backup tasks
    help            Show this help message

Examples:
    # Initialize .env file
    $(basename "$0") init

    # Backup MySQL database
    $(basename "$0") backup -t mysql -d mydb

    # Backup PostgreSQL database
    $(basename "$0") backup -t postgres -d mydb

    # Backup all databases (MySQL)
    $(basename "$0") backup -t mysql --all

    # Backup all databases (PostgreSQL)
    $(basename "$0") backup -t postgres --all

    # Add daily MySQL backup at 2am
    $(basename "$0") cron add "0 2 * * *" -t mysql

    # Add daily PostgreSQL backup at 3am
    $(basename "$0") cron add "0 3 * * *" -t postgres

    # List scheduled tasks
    $(basename "$0") cron list

Configuration:
    Create .env file in script directory or run '$(basename "$0") init'.
    See '$(basename "$0") backup --help' for available options.

EOF
}

# 显示备份帮助
show_backup_help() {
    cat << EOF
Usage: $(basename "$0") backup [options]

Backup MySQL or PostgreSQL databases to SQL files.

Supports:
    - MySQL (mysqldump)
    - PostgreSQL (pg_dump / pg_dumpall)

Options:
    Database:
        -t, --type TYPE              Database type: mysql or postgres (required)
        -d, --database DB            Database name
        --all                        Backup all databases (override .env config)

    Compression:
        -z, --compress               Enable gzip compression
        --no-compress                Disable compression (default)

    Docker:
        --docker-mysql CONTAINER     Docker container for MySQL
        --docker-postgres CONTAINER  Docker container for PostgreSQL
        --docker-mysql-env           Use MySQL Docker image env vars
        --docker-postgres-env        Use PostgreSQL Docker image env vars

    Output:
        -o, --output DIR             Output directory (default: current directory)

    Logging:
        --log-file FILE              Log file path (default: ./backupdb.log)
        --log-level LEVEL            Log level: DEBUG, INFO, WARN, ERROR (default: INFO)

    Help:
        -?, --help                   Show this help message

Configuration (.env):
    MySQL:
        MYSQL_DATABASE_URL=mysql://user:password@host:port/database
        MYSQL_ALL_DATABASES=true/false
        MYSQL_DOCKER_CONTAINER=container_name
        MYSQL_USE_DOCKER_ENV=true/false

    PostgreSQL:
        POSTGRES_DATABASE_URL=postgres://user:password@host:port/database
        POSTGRES_ALL_DATABASES=true/false
        POSTGRES_DOCKER_CONTAINER=container_name
        POSTGRES_USE_DOCKER_ENV=true/false

    General:
        USE_DOCKER=true/false
        TARGET_DIR=databases
        RCLONE_REMOTE_PATHS="remote1:path1 remote2:path2"
        OUTPUT_DIR=/path/to/backups

Examples:
    # Backup MySQL database
    $(basename "$0") backup -t mysql -d mydb

    # Backup PostgreSQL database
    $(basename "$0") backup -t postgres -d mydb

    # Backup all MySQL databases
    $(basename "$0") backup -t mysql --all

    # Backup all PostgreSQL databases
    $(basename "$0") backup -t postgres --all

    # Backup with compression
    $(basename "$0") backup -t mysql -z

    # Backup using Docker container
    $(basename "$0") backup -t mysql --docker-mysql my_mysql

EOF
}

# 解析 DATABASE_URL
# 格式: protocol://user:password@host:port/database?params
# 参数: $1=url, $2=prefix, $3=skip_database (可选，true 则不提取数据库名)
parse_database_url() {
    local url="$1"
    local prefix="$2"
    local skip_database="${3:-false}"

    if [[ -z "$url" ]]; then
        echo "Error: ${prefix}_DATABASE_URL is not set." >&2
        echo "Please configure it in .env file." >&2
        exit 1
    fi

    # 移除协议前缀
    local without_proto="${url#*://}"

    # 提取用户信息 (user:password@)
    local user_info="${without_proto%%@*}"
    local remaining="${without_proto#*@}"

    if [[ "$user_info" == "$without_proto" ]]; then
        # 没有用户信息
        DB_USER=""
        DB_PASS=""
    else
        DB_USER="${user_info%%:*}"
        DB_PASS="${user_info#*:}"
    fi

    # 提取主机和端口 (host:port/database)
    local host_port_db="${remaining%%\?*}"
    local host_port="${host_port_db%%/*}"
    
    # 检查是否有数据库名部分（URL 中是否有 /）
    local database=""
    if [[ "$host_port_db" == */* ]]; then
        database="${host_port_db#*/}"
    fi

    # 分离主机和端口
    DB_HOST="${host_port%%:*}"
    DB_PORT="${host_port#*:}"

    # 如果端口为空，使用默认值
    if [[ "$DB_PORT" == "$DB_HOST" ]]; then
        DB_PORT=""
    fi

    # 只有在不跳过时才提取数据库名
    if [[ "$skip_database" != "true" ]]; then
        DB_NAME="${database%%\?*}"
        DB_NAME="${DB_NAME%%\?*}"
        # 处理 _all 标记
        if [[ -z "$DB_NAME" || "$DB_NAME" == "_all" ]]; then
            DB_NAME=""
        fi
    else
        DB_NAME=""
    fi
}

# 初始化 .env 文件
init_env() {
    if [[ -f "$ENV_FILE" ]]; then
        echo "Environment file already exists: $ENV_FILE"
        read -r -p "Do you want to overwrite it? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    cat > "$ENV_FILE" << 'EOF'
# Database Configuration
# =====================

# MySQL Configuration
# -------------------
# Database URL (format: mysql://user:password@host:port/database)
MYSQL_DATABASE_URL=mysql://root:your_password_here@localhost:3306

# Backup all databases (true/false)
MYSQL_ALL_DATABASES=true

# Docker container name
MYSQL_DOCKER_CONTAINER=

# Use Docker image built-in environment variables (true/false)
# When enabled, reads MYSQL_ROOT_PASSWORD, MYSQL_DATABASE from container
MYSQL_USE_DOCKER_ENV=false

# PostgreSQL Configuration
# ------------------------
# Database URL (format: postgresql://user:password@host:port/database)
POSTGRES_DATABASE_URL=postgres://postgres:your_password_here@localhost:5432

# Backup all databases (true/false)
POSTGRES_ALL_DATABASES=true

# Docker container name
POSTGRES_DOCKER_CONTAINER=

# Use Docker image built-in environment variables (true/false)
# When enabled, reads POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, POSTGRES_PORT from container
POSTGRES_USE_DOCKER_ENV=false

# General Configuration
# ---------------------
# Use Docker mode (true/false)
USE_DOCKER=false

# Remote storage directory name
TARGET_DIR=databases

# Remote storage paths (rclone remote:path, multiple separated by space)
RCLONE_REMOTE_PATHS=""

# Output directory for backups
# OUTPUT_DIR=/var/backups

# Logging Configuration
# ---------------------
# Log file path (default: ./backupdb.log)
# LOG_FILE=/var/log/backupdb.log

# Log level: DEBUG, INFO, WARN, ERROR (default: INFO)
# LOG_LEVEL=INFO

EOF

    echo "Environment file created: $ENV_FILE"
    echo "Please edit it with your database configuration."
}

# 加载 .env 文件
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "Warning: Environment file not found: $ENV_FILE" >&2
        echo "Use '$(basename "$0") init' to create one." >&2
        return 1
    fi

    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # 移除行内注释（# 后面的内容）
        value="${value%%#*}"
        
        # 去除首尾空格
        value="$(echo "$value" | xargs)"
        
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        
        export "$key=$value"
    done < "$ENV_FILE"
    return 0
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 is not installed." >&2
        exit 1
    fi
}

# 执行 MySQL 备份
backup_mysql() {
    local db_host="$1" db_port="$2" db_user="$3" db_pass="$4"
    local db_name="$5" output_dir="$6" compress="$7" docker_container="$8"

    if [[ -z "$docker_container" ]]; then
        check_command mysqldump
    fi

    local today
    today=$(date +%Y%m%d)
    local backup_file="${output_dir}/mysql_${db_name:-all}_${today}.sql"

    local start_time
    start_time=$(date +%s)
    log "Starting MySQL backup..."
    log "  Host: $db_host:$db_port"
    log "  User: $db_user"
    log "  Database: ${db_name:-all}"
    [[ -n "$docker_container" ]] && log "  Docker: $docker_container"

    if [[ -n "$docker_container" ]]; then
        # Docker 方式
        local docker_args=("exec" "-i" "$docker_container" "mysqldump")
        docker_args+=("--host=$db_host" "--port=$db_port")
        docker_args+=("--user=$db_user")
        [[ -n "$db_pass" ]] && docker_args+=("--password=$db_pass")
        
        if [[ "$db_name" == "all" || -z "$db_name" ]]; then
            docker_args+=("--all-databases")
        else
            docker_args+=("--databases" "$db_name")
        fi
        
            if docker "${docker_args[@]}" > "$backup_file"; then
                local end_time
                end_time=$(date +%s)
                local duration=$(( end_time - start_time ))
                log "Backup completed: $backup_file (耗时: ${duration}s)"
            else
                log ERROR "错误：备份失败"
                rm -f "$backup_file"
                exit 1
            fi
    else
        # 本地方式
        local mysqldump_args=()
        mysqldump_args+=("--host=$db_host" "--port=$db_port" "--user=$db_user")
        [[ -n "$db_pass" ]] && mysqldump_args+=("--password=$db_pass")
        
        if [[ "$db_name" == "all" || -z "$db_name" ]]; then
            mysqldump_args+=("--all-databases")
        else
            mysqldump_args+=("--databases" "$db_name")
        fi
        
        if mysqldump "${mysqldump_args[@]}" > "$backup_file"; then
            local end_time
            end_time=$(date +%s)
            local duration=$(( end_time - start_time ))
            log "Backup completed: $backup_file (耗时: ${duration}s)"
        else
            log ERROR "错误：备份失败"
            rm -f "$backup_file"
            exit 1
        fi
    fi

    # 压缩处理
    if [[ "$compress" == "true" ]]; then
        if gzip "$backup_file"; then
            backup_file="${backup_file}.gz"
            log "已压缩: $backup_file"
        else
            log ERROR "错误：压缩失败"
            rm -f "$backup_file"
            exit 1
        fi
    fi

    ls -lh "$backup_file"
}

# 执行 PostgreSQL 备份
backup_postgres() {
    local db_host="$1" db_port="$2" db_user="$3" db_pass="$4"
    local db_name="$5" output_dir="$6" compress="$7" docker_container="$8"

    if [[ -z "$docker_container" ]]; then
        check_command pg_dump
        [[ -z "$db_name" ]] && check_command pg_dumpall
    fi

    local today
    today=$(date +%Y%m%d)
    local backup_file="${output_dir}/postgres_${db_name:-all}_${today}.sql"

    local start_time
    start_time=$(date +%s)
    log "Starting PostgreSQL backup..."
    log "  Host: $db_host:$db_port"
    log "  User: $db_user"
    log "  Database: ${db_name:-all}"
    [[ -n "$docker_container" ]] && log "  Docker: $docker_container"

    if [[ -n "$docker_container" ]]; then
        # Docker 方式
        if [[ -z "$db_name" ]]; then
            # 全量备份：使用 pg_dumpall
            local docker_args=("exec" "-i")
            [[ -n "$db_pass" ]] && docker_args+=("-e" "PGPASSWORD=$db_pass")
            docker_args+=("$docker_container" "pg_dumpall" "-h" "$db_host" "-p" "$db_port" "-U" "$db_user")
            
            if docker "${docker_args[@]}" > "$backup_file"; then
                local end_time
                end_time=$(date +%s)
                local duration=$(( end_time - start_time ))
                log "Backup completed: $backup_file (耗时: ${duration}s)"
            else
                log ERROR "错误：备份失败"
                rm -f "$backup_file"
                exit 1
            fi
        else
            # 单库备份：使用 pg_dump
            local docker_args=("exec" "-i")
            [[ -n "$db_pass" ]] && docker_args+=("-e" "PGPASSWORD=$db_pass")
            docker_args+=("$docker_container" "pg_dump" "-h" "$db_host" "-p" "$db_port" "-U" "$db_user" "$db_name")
            
            if docker "${docker_args[@]}" > "$backup_file"; then
                local end_time
                end_time=$(date +%s)
                local duration=$(( end_time - start_time ))
                log "Backup completed: $backup_file (耗时: ${duration}s)"
            else
                log ERROR "错误：备份失败"
                rm -f "$backup_file"
                exit 1
            fi
        fi
    else
        # 本地方式
        if [[ -z "$db_name" ]]; then
            # 全量备份：使用 pg_dumpall
            local pg_dumpall_args=("-h" "$db_host" "-p" "$db_port" "-U" "$db_user")
            [[ -n "$db_pass" ]] && export PGPASSWORD="$db_pass"
            
            if pg_dumpall "${pg_dumpall_args[@]}" > "$backup_file"; then
                local end_time
                end_time=$(date +%s)
                local duration=$(( end_time - start_time ))
                log "Backup completed: $backup_file (耗时: ${duration}s)"
            else
                log ERROR "错误：备份失败"
                rm -f "$backup_file"
                exit 1
            fi
            unset PGPASSWORD
        else
            # 单库备份：使用 pg_dump
            local pg_dump_args=("--host=$db_host" "--port=$db_port" "--username=$db_user")
            [[ -n "$db_pass" ]] && export PGPASSWORD="$db_pass"
            pg_dump_args+=("$db_name")
            
            if pg_dump "${pg_dump_args[@]}" > "$backup_file"; then
                local end_time
                end_time=$(date +%s)
                local duration=$(( end_time - start_time ))
                log "Backup completed: $backup_file (耗时: ${duration}s)"
            else
                log ERROR "错误：备份失败"
                rm -f "$backup_file"
                exit 1
            fi
            unset PGPASSWORD
        fi
    fi

    # 压缩处理
    if [[ "$compress" == "true" ]]; then
        if gzip "$backup_file"; then
            backup_file="${backup_file}.gz"
            log "已压缩: $backup_file"
        else
            log ERROR "错误：压缩失败"
            rm -f "$backup_file"
            exit 1
        fi
    fi

    ls -lh "$backup_file"
}

# 执行备份
do_backup() {
    local db_type="" db_name="" output_dir="" compress="false"
    local docker_container="" backup_all="false"
    local use_docker_env="false"
    local log_file="" log_level=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--type) db_type="$2"; shift 2 ;;
            -d|--database) db_name="$2"; shift 2 ;;
            --all) backup_all="true"; shift ;;
            -z|--compress) compress="true"; shift ;;
            --no-compress) compress="false"; shift ;;
            --docker-mysql) docker_container="$2"; shift 2 ;;
            --docker-postgres) docker_container="$2"; shift 2 ;;
            --docker-mysql-env) use_docker_env="mysql"; shift ;;
            --docker-postgres-env) use_docker_env="postgres"; shift ;;
            -o|--output) output_dir="$2"; shift 2 ;;
            --log-file) log_file="$2"; shift 2 ;;
            --log-level) log_level="$2"; shift 2 ;;
            -?|--help) show_backup_help; exit 0 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    # 验证数据库类型
    if [[ -z "$db_type" ]]; then
        echo "Error: Database type is required." >&2
        echo "Use: $(basename "$0") backup -t mysql|postgres" >&2
        exit 1
    fi

    case "$db_type" in
        mysql|postgres) ;;
        *) echo "Error: Invalid database type. Must be 'mysql' or 'postgres'." >&2; exit 1 ;;
    esac

    # 加载 .env 文件
    load_env

    if [[ -z "$LOG_FILE" ]]; then
        LOG_FILE="${SCRIPT_PATH}/backupdb.log"
    fi
    if [[ -z "$LOG_LEVEL" ]]; then
        LOG_LEVEL="INFO"
    fi

    if [[ -n "$log_file" ]]; then
        LOG_FILE="$log_file"
    fi
    if [[ -n "$log_level" ]]; then
        LOG_LEVEL="$log_level"
    fi

    # 如果未指定 docker 容器，从 .env 读取
    if [[ -z "$docker_container" ]]; then
        local use_docker="${USE_DOCKER:-false}"
        if [[ "$use_docker" == "true" ]]; then
            case "$db_type" in
                mysql) docker_container="${MYSQL_DOCKER_CONTAINER:-}" ;;
                postgres) docker_container="${POSTGRES_DOCKER_CONTAINER:-}" ;;
            esac
            if [[ -z "$docker_container" ]]; then
                log ERROR "错误：USE_DOCKER=true 但未设置 ${db_type} 容器名称"
                log ERROR "请设置 ${db_type^^}_DOCKER_CONTAINER 或使用 --docker-${db_type} 参数"
                exit 1
            fi
        fi
    fi

    # 检查是否使用 Docker 镜像内置环境变量
    if [[ "$use_docker_env" == "false" ]]; then
        case "$db_type" in
            mysql) [[ "${MYSQL_USE_DOCKER_ENV:-false}" == "true" ]] && use_docker_env="mysql" ;;
            postgres) [[ "${POSTGRES_USE_DOCKER_ENV:-false}" == "true" ]] && use_docker_env="postgres" ;;
        esac
    fi

    # 如果使用 Docker 镜像内置环境变量，从容器中读取配置
    DB_HOST="localhost"
    DB_PORT=""
    DB_USER=""
    DB_PASS=""
    DB_NAME=""
    
    if [[ -n "$use_docker_env" && "$use_docker_env" != "false" && -n "$docker_container" ]]; then
        log "使用 Docker 镜像内置环境变量: $use_docker_env"
        
        case "$use_docker_env" in
            mysql)
                # MySQL 镜像环境变量
                DB_USER="root"
                DB_PASS=$(docker exec "$docker_container" printenv MYSQL_ROOT_PASSWORD 2>/dev/null || true)
                DB_NAME=$(docker exec "$docker_container" printenv MYSQL_DATABASE 2>/dev/null || true)
                ;;
            postgres)
                # PostgreSQL 镜像环境变量
                DB_USER=$(docker exec "$docker_container" printenv POSTGRES_USER 2>/dev/null || echo "postgres")
                DB_PASS=$(docker exec "$docker_container" printenv POSTGRES_PASSWORD 2>/dev/null || true)
                DB_NAME=$(docker exec "$docker_container" printenv POSTGRES_DB 2>/dev/null || true)
                DB_PORT=$(docker exec "$docker_container" printenv POSTGRES_PORT 2>/dev/null || echo "5432")
                ;;
        esac
        
        # 检查是否获取到密码
        if [[ -z "$DB_PASS" ]]; then
            log ERROR "错误：无法从容器 $docker_container 获取密码"
            exit 1
        fi
        
        # 处理全量备份
        if [[ "$backup_all" == "true" ]]; then
            DB_NAME=""
            log "  Database: all (--all 参数)"
        elif [[ -n "$db_name" ]]; then
            # -d 参数覆盖
            DB_NAME="$db_name"
            log "  Database: $DB_NAME (-d 参数)"
        else
            # .env 配置
            local is_all_databases="false"
            case "$db_type" in
                mysql) is_all_databases="${MYSQL_ALL_DATABASES:-false}" ;;
                postgres) is_all_databases="${POSTGRES_ALL_DATABASES:-false}" ;;
            esac
            if [[ "$is_all_databases" == "true" ]]; then
                DB_NAME=""
                log "  Database: all (.env 配置)"
            else
                log "  Database: ${DB_NAME:-all}"
            fi
        fi
    else
        # 根据数据库类型获取 DATABASE_URL
        local db_url=""
        case "$db_type" in
            mysql) db_url="${MYSQL_DATABASE_URL:-}" ;;
            postgres) db_url="${POSTGRES_DATABASE_URL:-}" ;;
        esac

        # 判断是否全量备份
        # 优先级：--all 参数 > -d 参数 > .env 配置 > URL 中的数据库名
        local is_all_databases="false"
        
        if [[ "$backup_all" == "true" ]]; then
            # --all 参数：全量备份
            is_all_databases="true"
        elif [[ -n "$db_name" ]]; then
            # -d 参数：指定数据库
            is_all_databases="false"
        else
            # .env 配置
            case "$db_type" in
                mysql) is_all_databases="${MYSQL_ALL_DATABASES:-false}" ;;
                postgres) is_all_databases="${POSTGRES_ALL_DATABASES:-false}" ;;
            esac
        fi

        # 解析 DATABASE_URL
        if [[ "$is_all_databases" == "true" ]]; then
            # 全量备份：不从 URL 提取数据库名
            parse_database_url "$db_url" "$db_type" "true"
        else
            # 单库备份：从 URL 提取数据库名
            parse_database_url "$db_url" "$db_type" "false"
            # 如果指定了 -d 参数，覆盖 URL 中的数据库名
            [[ -n "$db_name" ]] && DB_NAME="$db_name"
            # 如果 URL 中数据库名为空，也视为全量备份
            [[ -z "$DB_NAME" ]] && is_all_databases="true"
        fi
    fi

    # 设置输出目录
    output_dir="${output_dir:-${OUTPUT_DIR:-.}}"

    # 检查输出目录
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            echo "Error: Cannot create output directory $output_dir" >&2
            exit 1
        }
    fi

    # 设置默认端口
    if [[ -z "$DB_PORT" ]]; then
        case "$db_type" in
            mysql) DB_PORT=3306 ;;
            postgres) DB_PORT=5432 ;;
        esac
    fi

    # 前置执行
    do_exec pre "$db_type"

    # 执行备份
    case "$db_type" in
        mysql)
            backup_mysql "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" \
                "$DB_NAME" "$output_dir" "$compress" "$docker_container"
            ;;
        postgres)
            backup_postgres "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" \
                "$DB_NAME" "$output_dir" "$compress" "$docker_container"
            ;;
    esac

    # 后置执行
    do_exec post "$db_type"
}

# 添加计划任务
cron_add() {
    local schedule="" db_type="" db_name="" compress="false"
    local docker_container="" extra_args=""
    local log_file="" log_level=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--type) db_type="$2"; shift 2 ;;
            -d|--database) db_name="$2"; extra_args+=" -d $2"; shift 2 ;;
            -z|--compress) compress="true"; extra_args+=" -z"; shift ;;
            --no-compress) extra_args+=" --no-compress"; shift ;;
            --docker-mysql) docker_container="$2"; extra_args+=" --docker-mysql $2"; shift 2 ;;
            --docker-postgres) docker_container="$2"; extra_args+=" --docker-postgres $2"; shift 2 ;;
            --log-file) log_file="$2"; extra_args+=" --log-file $2"; shift 2 ;;
            --log-level) log_level="$2"; extra_args+=" --log-level $2"; shift 2 ;;
            *)
                if [[ -z "$schedule" ]]; then
                    schedule="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$schedule" ]]; then
        echo "Error: Schedule is required." >&2
        echo "Usage: $(basename "$0") cron add \"0 2 * * *\" -t mysql" >&2
        exit 1
    fi

    if [[ -z "$db_type" ]]; then
        echo "Error: Database type is required." >&2
        echo "Usage: $(basename "$0") cron add \"0 2 * * *\" -t mysql" >&2
        exit 1
    fi

    case "$db_type" in
        mysql|postgres) ;;
        *) echo "Error: Invalid database type. Must be 'mysql' or 'postgres'." >&2; exit 1 ;;
    esac

    # 验证 crontab 格式（简单检查）
    local fields
    fields=$(echo "$schedule" | awk '{print NF}')
    if [[ "$fields" -lt 5 ]]; then
        echo "Error: Invalid cron schedule format." >&2
        echo "Expected 5 fields: minute hour day month weekday" >&2
        exit 1
    fi

    # 构建 cron 命令（先 cd 到脚本目录，备份文件会生成在当前目录）
    local cron_cmd
    cron_cmd="${schedule} cd ${SCRIPT_PATH} && ./$(basename "$0") backup -t ${db_type}"
    cron_cmd+="${extra_args} ${CRON_TAG}"

    # 检查是否已存在相同类型的备份任务
    if crontab -l 2>/dev/null | grep -q "${db_type}.*${CRON_TAG}"; then
        echo "Scheduled ${db_type} backup already exists. Use '$(basename "$0") cron del' first."
        crontab -l 2>/dev/null | grep "${db_type}.*${CRON_TAG}"
        exit 1
    fi

    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    
    log "Scheduled backup added:"
    log "  Type:     $db_type"
    log "  Schedule: $schedule"
    log "  Command:  ${SCRIPT_PATH}/$(basename "$0") backup -t $db_type${extra_args}"
    log ""
    log "Current crontab:"
    crontab -l 2>/dev/null | grep "$CRON_TAG" || true
}

# 删除计划任务
cron_del() {
    local db_type=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--type) db_type="$2"; shift 2 ;;
            -?|--help)
                cat << EOF
Usage: $(basename "$0") cron del [options]

Remove scheduled backup tasks.

Options:
    -t, --type TYPE    Database type: mysql or postgres (optional)
    -?, --help         Show this help message

Examples:
    $(basename "$0") cron del              # Remove all backup tasks
    $(basename "$0") cron del -t mysql     # Remove MySQL backup task only
    $(basename "$0") cron del -t postgres  # Remove PostgreSQL backup task only

EOF
                exit 0
                ;;
            *) shift ;;
        esac
    done

    # 1. 检查是否存在受当前脚本管理的任务
    if [[ -z "$db_type" ]]; then
        if ! crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
            echo "No scheduled backup found."
            exit 0
        fi
        log "Removing all scheduled backups..."
    else
        case "$db_type" in
            mysql|postgres) ;;
            *) echo "Error: Invalid database type. Must be 'mysql' or 'postgres'." >&2; exit 1 ;;
        esac

        if ! crontab -l 2>/dev/null | grep -q "${db_type}.*${CRON_TAG}"; then
            echo "No scheduled ${db_type} backup found."
            exit 0
        fi
        log "Removing scheduled ${db_type} backup..."
    fi
    
    # 2. 安全过滤并重新写入（核心修复点）
    local remaining_cron
    if [[ -z "$db_type" ]]; then
        # 移除所有带标记的备份任务，保留其他任务
        remaining_cron=$(crontab -l 2>/dev/null | grep -v "$CRON_TAG" || true)
    else
        # 仅移除指定类型的备份任务，保留其他任务
        remaining_cron=$(crontab -l 2>/dev/null | grep -v "${db_type}.*${CRON_TAG}" || true)
    fi

    # 3. 根据剩余内容决定重写还是彻底清空
    if [[ -n "$remaining_cron" ]]; then
        # 如果还有其他任务，则安全覆盖
        echo "$remaining_cron" | crontab -
    else
        # 如果什么都不剩了，使用 -r 参数安全地移除整个用户的 crontab
        crontab -r 2>/dev/null || true
    fi
    
    log "Scheduled backup removed successfully."
}

# 列出计划任务
cron_list() {
    if ! crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        echo "No scheduled backup found."
        exit 0
    fi

    echo "Scheduled backup tasks:"
    crontab -l 2>/dev/null | grep "$CRON_TAG"
}

# 管理计划任务
do_cron() {
    local action="${1:-}"
    shift || true
    
    case "$action" in
        add)
            cron_add "$@"
            ;;
        del|delete|remove)
            cron_del "$@"
            ;;
        list|ls)
            cron_list
            ;;
        *)
            cat << EOF
Usage: $(basename "$0") cron <action> [options]

Manage scheduled backup tasks.

Actions:
    add <schedule> -t <type> [options]   Add a scheduled backup
    del [-t <type>]                      Remove scheduled backup (all or by type)
    list                                 List scheduled backups

Options:
    -t, --type TYPE              Database type: mysql or postgres
    -d, --database DB            Database name
    -z, --compress               Enable compression
    --docker-mysql CONTAINER     Docker container for MySQL
    --docker-postgres CONTAINER  Docker container for PostgreSQL
    --log-file FILE              Log file path
    --log-level LEVEL            Log level: DEBUG, INFO, WARN, ERROR

Examples:
    $(basename "$0") cron add "0 2 * * *" -t mysql                    # Daily at 2am for MySQL
    $(basename "$0") cron add "0 */6 * * *" -t postgres -z            # Every 6 hours with compression
    $(basename "$0") cron add "0 2 * * *" -t mysql --docker-mysql cnt # Docker mode
    $(basename "$0") cron del -t mysql                                # Remove MySQL backup task
    $(basename "$0") cron del                                         # Remove all backup tasks
    $(basename "$0") cron list

EOF
            exit 1
            ;;
    esac
}

# 主函数
main() {
    local command="${1:-help}"
    
    case "$command" in
        backup)
            shift
            do_backup "$@"
            ;;
        init)
            init_env
            ;;
        cron)
            shift
            do_cron "$@"
            ;;
        help|-?|--help)
            show_help
            ;;
        *)
            echo "Unknown command: $command" >&2
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 如果直接执行脚本则运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
