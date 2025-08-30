#!/usr/bin/env bash

#####
### 从远程文件升级本文件夹下的所有脚本
###
### 每个需要更新的文件中添加源地址
### # ORIGIN: https://myfiles.com/origin-file.sh
###
####

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

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

find . -mindepth 2 -maxdepth 2 -type f \( -name "*.sh" -o -name "*.ps1" -o -name "*.py" \) -not -wholename "./.upgrade.sh" -print0 |
  while IFS= read -r -d '' filename; do
    url=$(awk '/^# ORIGIN:/ {print $3}' "$filename")
    download_and_replace "$url" "$filename"
  done

echo "All files have been updated."