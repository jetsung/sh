#!/usr/bin/env bash

#============================================================
# File: totp2md.sh
# Description: 将 TOTP 二维码转换为 Markdown 表格
# URL: https://s.fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/30f7cb75c6714359bbd9673f97c70781/raw/HEAD/totp2md.sh
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-18
# UpdatedAt: 2025-08-18
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi
 
TOTP_DIR="${1:-TOTP}"
OUTPUT_FILE="${2:-qr_codes.md}"
 
# Initialize Markdown table header
echo "| SiteName | Username | Secret | Text | Mark |" > "$OUTPUT_FILE"
echo "|:---|:---|:---|:---|:---|" >> "$OUTPUT_FILE"
 
# Find all SVG and PNG files in the specified directory
find "$TOTP_DIR" -type f \( -name "*.svg" -o -name "*.png" \) | while read -r file; do
    qr_text=$(zbarimg "$file" | head -n 1 2>/dev/null)
    qr_text=${qr_text/QR-Code:/}
    # qr_text=$(qrtool decode "$file" 2>/dev/null)
    # qr_text=$(totp-qr --uri "$file" 2>/dev/null)
 
    filename="$file"
 
    sitename=""
    username=""
    secret=""
    text="$qr_text"
    issuer=""
 
    # # Handle otpauth URLs
    if [[ "$qr_text" =~ ^otpauth://totp/ ]]; then
        label=$(echo "$qr_text" | grep -oP '(?<=totp/).*?(?=\?)')
        label=$(printf '%b' "${label//%/\\x}")
 
        issuer=$(echo "$qr_text" | grep -oP 'issuer=\K[^&]*' | head -1)
        issuer=$(printf '%b' "${issuer//%/\\x}")
 
        if [ -n "$label" ]; then
            if [[ "$label" =~ ^([^:]+):(.+)$ ]]; then
                sitename="${BASH_REMATCH[1]}"
                username="${BASH_REMATCH[2]}"
            else
                username="$label"
            fi
        fi
 
        if [ -z "$issuer" ]; then
            issuer="$sitename"
        fi
 
        secret=$(echo "$qr_text" | grep -oP 'secret=\K[^&]*' | head -1)
 
    elif [[ "$qr_text" =~ ^ms-msa:// ]]; then
        username=$(echo "$qr_text" | grep -oP 'uaid=\K[^&]*' | head -1)
        secret=$(echo "$qr_text" | grep -oP 'code=\K[^&]*' | head -1)
    else
        sitename="$filename"
        username=""
        secret=""
    fi
 
    text=${text//|/\\|}
 
    if [ -z "$issuer" ]; then
        issuer=$(basename "$filename")
    fi
    issuer_str="[$issuer]($filename)"
 
    echo "filename: $filename"
    echo "sitename: $issuer"
    echo "username: $username"
    echo "secret:   $secret"
    echo "text:     $text"
    echo
 
    echo "| $issuer_str | $username | $secret | $text |  |" >> "$OUTPUT_FILE"
done
 
echo "Markdown table generated in $OUTPUT_FILE"

###
#
# 参数1: TOTP 目录
# 参数2: 输出文件
#
# 示例:
# ./totp2md.sh TOTP qr_codes.md
#
###
