#!/usr/bin/env bash

#####
###
### 从远程文件升级本文件夹下的所有脚本
###
### 1. 每个需要更新的文件中添加源地址
### # ORIGIN1: https://myfiles.com/origin-sh.sh
###
### 2. 执行本脚本：bash __upgrade.sh
###
####

download_and_replace() {
  local url=$1
  local filename=$2
  local temp_file
  temp_file=$(mktemp)

  # Download the file to a temporary file
  wget "$url" -O "$temp_file" --quiet

  # Check the status code
  local status=$?
  local currentfile=${filename#*/}
  if [ $status -eq 0 ]; then
    mv "$temp_file" "$filename"
    echo "$currentfile is updated from $url"
  else
    rm -f "$temp_file"
    echo "Failed to download $url for file $currentfile (Status code: $status)"
  fi
}

find . -type f -name "*.sh" -not -wholename "./__upgrade.sh" -exec awk '/^# ORIGIN:/ {print FILENAME, $3}' {} \; |
  while read -r filename url; do
    download_and_replace "$url" "$filename"
  done
