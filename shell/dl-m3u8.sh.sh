#!/bin/bash

##
## 将视频转换为 H.264 编码的 MP4 视频
## 
## 用法：
## m3u8-dl.sh abc.m3u8 filename.mp4: 参数一为 m3u8 地址；参数二为保存的文件名，默认为 move.mp4。
##

ffmpeg_download() {
  ffmpeg -user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 11_1_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.182 Safari/537.36" -i "${1}" -c copy -bsf:a aac_adtstoasc "${2}"
}

main() {
  if [[ -z "${1}" ]] ;then
    echo "Miss param url."
    exit 1
  fi

  URL="${1}"
  NAME="move.mp4"

  [[ -n "${2}" ]] && NAME="${2}"

  ffmpeg_download "${URL}" "${NAME}"
}

main "$@" || exit 1
