#!/usr/bin/env bash

#============================================================
# File: google-cloud-token.sh
# Description: 获取 google cloud token
# URL: 
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-07-28
# UpdatedAt: 2025-07-28
#============================================================

if [[  -n "${DEBUG:-}" ]]; then
    set -x
else
    set -euo pipefail
fi

# 客户端配置
if [[ -z "${CLIENT_ID:-}" ]]; then
  read -r -p "请输入客户端 ID: " CLIENT_ID
fi

if [[ -z "${CLIENT_SECRET:-}" ]]; then
  read -r -p "请输入客户端密钥: " CLIENT_SECRET
fi

REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
SCOPE="https://www.googleapis.com/auth/userinfo.profile"

echo "client id: $CLIENT_ID"
echo

# 生成授权 URL
AUTH_URL="https://accounts.google.com/o/oauth2/auth?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&response_type=code&scope=$SCOPE&access_type=offline&prompt=consent"
echo "请在浏览器中打开以下 URL 并授权："
echo "$AUTH_URL"
echo

OS=$(uname)
if [[ "$OS" == "Darwin" ]]; then
  open "$AUTH_URL"  # macOS
elif [[ "$OS" == "Linux" && -x "$(command -v xdg-open)" ]]; then
  xdg-open "$AUTH_URL"  # Linux
else
  echo "请手动复制到浏览器"
fi

# 用户输入授权码
read -r -p "请输入授权码: " AUTH_CODE

# 交换授权码获取 refresh_token
RESPONSE=$(curl -s "https://oauth2.googleapis.com/token" \
  -d "code=$AUTH_CODE" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "redirect_uri=$REDIRECT_URI" \
  -d "grant_type=authorization_code")

echo "响应："
echo "$RESPONSE"
echo

# 提取 refresh_token（需要 jq 工具）
if command -v jq >/dev/null 2>&1; then
  REFRESH_TOKEN=$(echo "$RESPONSE" | jq -r '.refresh_token')
  echo "Refresh Token: $REFRESH_TOKEN"
else
  echo "请安装 jq 以提取 refresh_token，或手动检查响应"
fi