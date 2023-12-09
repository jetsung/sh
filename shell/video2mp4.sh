#!/bin/bash

##
## 将视频转换为 H.264 编码的 MP4 视频
##
## 用法：
## c2mp4.sh: 忽略参数时，默认为将当前目录下的所有格式的视频转换为 MP4。
##           此处所有格式指后缀为：
##             .avi .AVI .wmv .WMV .rmvb .RMVB .rm .RM .mpg .MPG .mpeg .MPEG .3gp .3GP
##
## c2mp4.sh .wmv: 将当前目录下的所有 wmv 格式视频转换为 MP4。
##
## c2mp4.sh .avi a.avi 或 c2mp4.sh .avi a: 将 a.avi 视频转换为 MP4。
##
##
##   -c:a mp3 mp3 可修改为 aac 等音频格式码。不修改编码则为 copy
##   -c:v libx265 libx265 可修改为 h264、libx264（H.264 格式）和 libx265（H.265 格式）
##        其中 H.265 占用资源比 H.264 少一点，但大部分浏览器不支持播放。
##        hevc_amf 使用 amd GPU 加速转换（目前仅支持 Windows 平台）
##

ffmpeg_file() {
  ffmpeg -i "${1}" -max_muxing_queue_size 1024 -c:a copy -c:v libx264 -y "${2}"
}

ext2mp4() {
  # LIST=$(find ./ -type f \( -name "*.avi" -o -name "*.wmv" -o -name "*.mp4" -o -name "*.mpg" -o -name "*.3gp" \))
  EXT="${1}"
  printf "\e[1;33m❤ From %s to .mp4\e[m\n" "${EXT}"

  while IFS= read -r -d '' NAME; do
    printf "\n\e[0;33m%s\e[0m to \e[0;33m%s\e[0m\n" "${NAME##*/}" "${NEWFNAME##*/}"
    NEWFNAME=${NAME//${EXT}/.mp4}

    #ffmpeg -i "${name}" -max_muxing_queue_size 1024 -c:a copy -c:v libx264 -y "${newfname}"
    ffmpeg_file "${NAME}" "${NEWFNAME}"
  done < <(find ./ -name "*${EXT}" -print0)
}

file2mp4() {
  EXT="${1}"
  NAME="${2%%.*}"

  NEWFNAME="${NAME}.mp4"
  printf "\n\e[0;33m%s\e[0m to \e[0;33m%s\e[0m\n" "${NAME}${EXT}" "${NEWFNAME}"

  ffmpeg_file "${NAME}" "${NEWFNAME}"
}

all() {
  EXTS=".avi .wmv .rmvb .rm .mpg .mpeg .3gp"
  while IFS= read -r -d ' ' EXT; do
    ext2mp4 "${EXT}"
    ext2mp4 "${EXT^^}"
  done < <(echo "${EXTS}")
}

main() {
  if [[ -z "${1}" ]]; then
    all
  else
    if [[ -n "${2}" ]]; then
      file2mp4 "${1}" "${2}"
    else
      ext2mp4 "${1}"
    fi
  fi
}

main "$@" || exit 1
