#!/usr/bin/env bash

#============================================================
# File: ffmpeg-dl.sh
# Description: 通过 ffmpeg 下载 m3u8 视频
# URL: 
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-03-14
# UpdatedAt: 2025-03-14
#============================================================

judgment_parameters() {
  while getopts "n:u:" opt; do
    case "$opt" in
      n)
        if [[ -z "${OPTARG:?error: Please specify the correct file name.}" ]]; then
            exit 1
        fi
        NAME="$OPTARG"
        ;;
      u)
        if [[ -z "${OPTARG:?error: Please specify the correct url.}" ]]; then
            exit 1
        fi
        URL="$OPTARG"
        ;;
      \?)
        echo "Usage: $0 [-n <filename>] [-u <url>]"
        exit 1
        ;;
    esac
  done
}

ffmpeg_download() {
  ffmpeg -user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 11_1_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.182 Safari/537.36" -i "$URL" -c copy -bsf:a aac_adtstoasc "$NAME"
}

main() {
  judgment_parameters "$@"

  if [[ -z "$NAME" ]]; then
    # 生成随机名称
    NAME="$(tr -dc 'a-zA-Z0-9' < /dev/urandom| head -c 10).mp4"
  fi

  ffmpeg_download
}

main "$@"
