#!/usr/bin/env bash

DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/protocolbuffers/protobuf/releases/latest" | jq '.tag_name, .assets[].browser_download_url' | grep linux-x86_64)

TMP_PATH=$(mktemp -d)

curl -fsSL -o "${TMP_PATH}/protoc.zip" "${DOWNLOAD_URL}"
cd "${TMP_PATH}" || exit

unzip protoc.zip

cp bin/protoc /usr/local/bin/

protoc --version