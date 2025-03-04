#!/usr/bin/env bash

#============================================================
# 文件名: protoc.sh
# 描述: 安装 protobuf
# URL: 
# 作者: Jetsung Chan <i@jetsung.com>
# 版本: 1.0
# 创建日期: 
# 更新日期: 
#============================================================

DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/protocolbuffers/protobuf/releases/latest" | jq -r '.tag_name, .assets[].browser_download_url' | grep linux-x86_64)

TMP_PATH=$(mktemp -d)

curl -fsSL -o "${TMP_PATH}/protoc.zip" "${DOWNLOAD_URL}"
cd "${TMP_PATH}" || exit

unzip protoc.zip

cp bin/protoc /usr/local/bin/
cp -r include/google /usr/include/

protoc --version