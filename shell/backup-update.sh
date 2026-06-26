#!/usr/bin/env bash

#============================================================
# File: backup-update.sh
# Description: 更新服务器中的 Docker 镜像和备份数据
# URL: https://fx4.cn/backupupdate
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.0
# CreatedAt: 2025-07-12
# UpdatedAt: 2026-06-26
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

script_name=$(basename "$0")
script_path="$(pwd)"

log_file="${script_name%.*}.log"
list_file=".docker_sync"

docker_path="${docker_path:-/root/dockers}"

backup_file="backup.sh"
update_file="update.sh"

interval_day='*'

cron_run_path="cronrun.sh"

# Docker 项目的目录深度
mindepth=2
maxdepth=2

# 备份的额外参数
backup_arg_extra=""

# 提取参数
judgment_parameters() {
  while getopts "d:p:b:s:u:m:e:hi" opt; do
    case "$opt" in
      i)
        # 安装
        setup=1
        ;;
      d)
        # 每隔多少天备份一次
        interval_day="$OPTARG"
        ;;
      p)
        # Docker 路径
        docker_path="$OPTARG"
        ;;
      b)
        # 备份：带参数即启用，不带参数也启用（因为 -b 出现即启用）
        backup_arg="yes"
        ;;
      s)
        # 子目录脚本运行：带参数即启用，不带参数也启用
        subrun_arg="yes"
        ;;
      u)
        # 更新：带参数即启用，不带参数也启用
        update_arg="yes"
        ;;    
      e)
        # 备份的额外参数
        if [[ -z "${OPTARG:-}" ]]; then
          echo "Error: -e requires a non-empty argument" >&2
          exit 1
        fi
        backup_arg_extra="$OPTARG"
        ;;
      m)
        # 文件夹深度
        if [[ -z "${OPTARG:-}" ]]; then
          echo "Error: -i requires a non-empty argument" >&2
          exit 1
        fi
        mindepth=$(echo "${OPTARG:-}" | cut -d '-' -f 1)
        maxdepth=$(echo "${OPTARG:-}" | cut -d '-' -f 2)
        if [[ -z "$mindepth" ]]; then
          echo "Error: -i requires a non-empty argument" >&2
          exit 1
        fi
        if [[ -z "$maxdepth" ]]; then
          maxdepth="$mindepth"
        fi
        ;;
      h)
        # 帮助
        cat <<EOF
用法: $0 [选项]

选项:
  -i          安装 crontab 定时任务
  -d <天数>   每隔多少天备份一次 (默认: 每天)
  -m <深度>   文件夹深度 mindepth-maxdepth (默认: 2-2)
  -p <路径>   Docker 项目路径 (默认: /root/dockers)
  -b          启用备份功能
  -u          启用更新 Docker 镜像功能
  -s          启用子目录脚本运行
  -e <参数>   备份的额外参数
  -h          显示此帮助信息

示例:
  $0 -i -p ~/dockers -d 5 -b -u
  安装定时任务: 每5天执行一次备份和更新

  $0 -i -p ~/dockers -b -u -s
  安装定时任务: 每天执行备份、更新,并运行子目录脚本

  $0 -b -u
  手动切换备份和更新开关
EOF
        exit 0
        ;;            
      \?)
        # 无效选项
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
      :)
        # 缺少选项参数
        echo "Option -$OPTARG requires an argument" >&2
        exit 1
        ;;
    esac
  done
}

# 更新列表镜像，.docker_sync 每行一个文件夹。
update_list() {
  while IFS=$'\n' read -r _fname; do
    _docker_folder="$docker_path/$_fname"
    _docker_folder_file="$_docker_folder/docker-compose.yml"
    if [ -f "$_docker_folder_file" ]; then
      pushd "$_docker_folder" > /dev/null 2>&1 || exit 1
      	if [ -f "$update_file" ]; then
            bash "$update_file"
        else
            docker compose pull
            docker compose down
            docker compose up -d
        fi
      popd > /dev/null 2>&1
    fi
  done < "$list_file"
}

# 备份所有数据
backup_all() {
  while read -r line; do
    folder_path=$(dirname "$line")
    pushd "$folder_path" > /dev/null 2>&1
      echo "badkup folder: $folder_path"
      # shellcheck disable=SC2086
      bash "$backup_file" $backup_arg_extra < /dev/null
    popd > /dev/null 2>&1
  done < <(find "$docker_path" -mindepth "$mindepth" -maxdepth "$maxdepth" -type f -name "$backup_file")
}

# 检查输入参数是否为数字且在指定范围内
get_every_day() {
  local input="${1:-3}"  # 使用 local 声明局部变量
  # 使用正则表达式和算术比较，简化逻辑
  if [[ $input =~ ^[0-9]+$ ]] && (( input < 30 )) && (( input > 0 )); then
    echo "$input"
  else
    echo 3
  fi
}

# 设置
setup_setting() {
    # 设置 docker 路径
    if [[ -n "$docker_path" ]]; then
        sed -i "s#^docker_path=.*#docker_path=\"$docker_path\"#" "$cron_file_path"
    fi

    # 设置脚本运行路径
    sed -i "s#^cron_run_path=.*#cron_run_path=\"$cron_file_path\"#" "$cron_file_path"
    
    # 备份的额外参数
    sed -i "s#^backup_arg_extra=.*#backup_arg_extra=\"$backup_arg_extra\"#" "$cron_file_path"

    # 注释掉 setup 行
    sed -i '/^\s*setup\s*$/s/^/#/' "$cron_file_path"

    # 更新深度
    sed -i "s#^mindepth=.*#mindepth=\"$mindepth\"#" "$cron_file_path"
    sed -i "s#^maxdepth=.*#maxdepth=\"$maxdepth\"#" "$cron_file_path"
}

# 生成 crontab 任务
setup_crontab() {
  local every_day='*'
  if [[ "$interval_day" != '*' ]]; then
    every_day="*/$interval_day"
  fi

  # 生成一个随机分钟数（0-59之间）
  random_minute=$(shuf -i 0-59 -n 1)
  
  # 生成一个随机小时数（0-23之间）
  random_hour=$(shuf -i 0-8 -n 1)

  cron_dir="/etc/cron.d/"

  cron_str="$random_minute $random_hour $every_day * * $(whoami) cd $script_path; ./$cron_file_path"
  cron_path="${cron_dir}${cron_file_path%.*}"

  echo "$cron_str" > "$cron_path"
  # echo "cron str: $cron_str"
  echo "crontab setup at: $cron_path"

  real_str=$(cat "$cron_path")
  printf "\033[40m\033[1;33m%s\033[0m\n" "$real_str"
  
  restart_crontab
}

# 重启 crontab 服务
restart_crontab() {
  systemctl restart cron
}

# 安装 crontab 服务
setup() {
    echo ""
    echo "setup crontab run"

    local pre_day='every'
    # 间隔天数
    if [[ "$interval_day" != '*' ]]; then
      interval_day=$(get_every_day "${interval_day:-3}")
      pre_day="$interval_day"
    fi

    cron_file_path="${pre_day}_cronrun.sh"
    
    echo "setup new cron file to $cron_file_path"

    cp "$0" "$cron_file_path"  

    # 设置
    setup_setting

    # 安装 crontab 服务
    setup_crontab  
}

# 备份
backup() { backup_all; }

# 更新
update() { update_list; }  

# 此脚本的子目录,包含 cronrun.sh 脚本
subdirs_run() {
  echo "subdirs run cronrun.sh"
  find . -maxdepth 2 -name cronrun.sh -execdir bash cronrun.sh \;
}

# 备份更新开关
switch() {
  # 源文件,不修改任何配置信息
  if [[ "$cron_run_path" != "cronrun.sh" ]]; then
    local backup_arg="${backup_arg:-}"
    local update_arg="${update_arg:-}"
    local subrun_arg="${subrun_arg:-}"

    echo ""
    echo "switch backup/update"

    if [[ -n "$backup_arg" ]]; then
      echo "  backup: $backup_arg"
      
      if [[ "$backup_arg" = "yes" ]]; then
        # 解除注释 backup 行
        sed -i '/^\s*#\s*backup\s*$/s/# //' "$cron_file_path"
      else
        # 注释掉 backup 行
        sed -i '/^\s*backup\s*$/s/^/# /' "$cron_file_path"        
      fi
    fi

    if [[ -n "$update_arg" ]]; then
      echo "  update: $update_arg"
      
      if [[ "$update_arg" = "yes" ]]; then
        sed -i '/^\s*#\s*update\s*$/s/# //' "$cron_file_path"
        # 解除注释 update 行
      else
        # 注释掉 update 行
        sed -i '/^\s*update\s*$/s/^/# /' "$cron_file_path"
      fi
    fi

    if [[ -n "$subrun_arg" ]]; then
      echo "  subdir run: $subrun_arg"
      
      if [[ "$subrun_arg" = "yes" ]]; then
        sed -i '/^\s*#\s*subdirs_run\s*$/s/# //' "$cron_file_path"
        # 解除注释 subrun 行
      else
        # 注释掉 subrun 行
        sed -i '/^\s*subdirs_run\s*$/s/^/# /' "$cron_file_path"
      fi
    fi
  fi 
}

main() {
  judgment_parameters "$@"

  if [ -n "${setup:-}" ]; then
    echo "docker_path: $docker_path"
    echo "interval_day: $interval_day"
    
    setup

    cron_run_path="$cron_file_path"
    # 备份更新开关
    switch
    exit 0
  fi

  if [[ "$cron_run_path" != "cronrun.sh" ]]; then
    cron_file_path="$cron_run_path"

    # 备份更新开关
    switch

    {
      echo ""
      date -R

      # backup

      # update

      # subdirs_run
    } >> "$log_file"
  fi
}

main "$@" || exit 1

#
# curl -L https://fx4.cn/backupupdate -o backup-update.sh
#
# 查看帮助: bash backup-update.sh -h
# 安装定时计划,每5天执行备份和更新: bash backup-update.sh -i -p ~/dockers -d 5 -b -u

# 1. 在每个 docker 服务的文件夹下，创建 update.sh 和 backup.sh
# 2. 生成 crontab 任务: bash backup-update.sh -i -p ~/dockers -d 5 -b -u
# 3. 将需要定时更新（docker compose pull）的 Docker 项目文件夹添加到 .docker_sync 文件中，每行一个文件夹(只需要文件夹本名即可)
#    如 ~/dockers/minio => minio
#    该文件夹下,需要有 update.sh 文件
# *4. 后期可通过 ./file.sh -b -u 来切换备份和更新
# 5. 本脚本目录下的所有子目录,包含 cronrun.sh 脚本则会被执行
