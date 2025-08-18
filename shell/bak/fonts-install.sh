#!/usr/bin/env bash

##
# 安装当前目录及子目录下的字体
##

set -e

CUSTOM_FONTS="/usr/share/fonts/custom"

[ -d $CUSTOM_FONTS ] || sudo mkdir -p $CUSTOM_FONTS

for EXT in ".otf" ".ttf"; do
  while IFS= read -r -d '' _V; do
      printf "cp font: %s\n" "$_V"
      sudo chmod 644 "$_V"
      sudo cp "$_V" "$CUSTOM_FONTS"
  done < <(sudo find . -name "*$EXT" -type f -print0)
done

pushd "$CUSTOM_FONTS" >/dev/null || exit 1
  sudo mkfontdir
  sudo mkfontscale
  sudo fc-cache
popd >/dev/null || exit 1