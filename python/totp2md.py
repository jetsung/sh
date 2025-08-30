#!/usr/bin/env python3

#============================================================
# File: totp2md.py
# Description: 将 TOTP 二维码转换为 Markdown 表格
# URL: https://s.fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/30f7cb75c6714359bbd9673f97c70781/raw/HEAD/totp2md.py
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-18
# UpdatedAt: 2025-08-18
#============================================================


import os
import re
import subprocess
import urllib.parse
from pathlib import Path
import argparse

def decode_qr_image(file_path):
    """使用 zbarimg 读取二维码内容"""
    try:
        result = subprocess.run(
            ['zbarimg', str(file_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        lines = result.stdout.strip().splitlines()
        if lines:
            qr_text = lines[0].strip()
            if qr_text.startswith("QR-Code:"):
                qr_text = qr_text[len("QR-Code:"):]
            return qr_text.strip()
    except subprocess.CalledProcessError:
        pass  # zbarimg 无法识别
    except FileNotFoundError:
        print("错误: 找不到 zbarimg，请确保已安装 ZBar 并加入 PATH。")
        exit(1)
    return None


def parse_otpauth_uri(uri):
    """解析 otpauth://totp/ URI"""
    sitename = ""
    username = ""
    secret = ""
    issuer = ""

    try:
        from urllib.parse import urlparse, parse_qs
        parsed = urlparse(uri)
        query = parse_qs(parsed.query, keep_blank_values=True)
        secret = query.get('secret', [None])[0] or ""

        label = parsed.path.lstrip('/')  # e.g., Google:john@gmail.com
        label = urllib.parse.unquote(label)

        issuer = query.get('issuer', [None])[0] or ""
        if issuer:
            issuer = urllib.parse.unquote(issuer)

        if ':' in label:
            parts = label.split(':', 1)
            sitename = parts[0].strip()
            username = parts[1].strip()
        else:
            username = label

        if not issuer:
            issuer = sitename or ""

    except Exception as e:
        print(f"解析 otpauth 失败: {e}")
    return sitename, username, secret, issuer


def parse_ms_msa_uri(uri):
    """解析 ms-msa:// URI，提取 uaid 和 code"""
    username = ""
    secret = ""
    try:
        query_string = uri.split('//', 1)[1]
        # 使用 parse_qs 解析
        query = urllib.parse.parse_qs(query_string, keep_blank_values=True)

        username = query.get('uaid', [None])[0] or ""
        secret = query.get('code', [None])[0] or ""

        # 返回值：sitename, username, secret, issuer
        return "", username, secret, "Microsoft"
    except Exception as e:
        print(f"解析 ms-msa 失败: {e}")
    return "", "", "", "Microsoft"


def main(input_dir, output_file):
    file_dir = Path(input_dir)
    if not file_dir.exists():
        print(f"目录不存在: {file_dir}")
        exit(1)

    # 获取所有 .svg 和 .png 文件
    image_files = []
    image_files.extend(file_dir.rglob("*.svg"))
    image_files.extend(file_dir.rglob("*.png"))

    # 按路径排序
    image_files.sort(key=lambda x: str(x).lower())

    # 写入 Markdown 表头
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("| SiteName | Username | Secret | Text | Mark |\n")
        f.write("|:---|:---|:---|:---|:---|\n")

        for file_path in image_files:
            qr_text = decode_qr_image(file_path)
            if not qr_text:
                print(f"无法读取二维码: {file_path}")
                continue

            # 转义 Markdown 中的 |
            text_display = qr_text.replace('|', r'\|')

            sitename = ""
            username = ""
            secret = ""
            issuer = ""

            if qr_text.startswith("otpauth://totp/"):
                sitename, username, secret, issuer = parse_otpauth_uri(qr_text)
                if not issuer:
                    issuer = sitename or file_path.stem
            elif qr_text.startswith("ms-msa://"):
                sitename, username, secret, issuer = parse_ms_msa_uri(qr_text)
            else:
                # 其他类型
                sitename = file_path.stem
                username = ""
                secret = ""
                issuer = file_path.stem

            # 构造 SiteName 列：[issuer](相对路径)
            relative_path = file_path.as_posix()
            issuer_str = f"[{issuer}]({relative_path})"

            # 输出调试信息
            print(f"filename: {file_path}")
            print(f"sitename: {issuer}")
            print(f"username: {username}")
            print(f"secret:   {secret}")
            print(f"text:     {qr_text}")
            print()

            # 写入表格行
            f.write(f"| {issuer_str} | {username} | {secret} | `{text_display}` |  |\n")

    print(f"✅ Markdown 表格已生成: {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="从 TOTP 二维码图片生成 Markdown 表格")
    parser.add_argument(
        '-i', '--input',
        default="TOTP",
        help="二维码图片目录 (默认: TOTP)"
    )
    parser.add_argument(
        '-o', '--output',
        default="qr_codes.md",
        help="输出 Markdown 文件路径 (默认: qr_codes.md)"
    )

    args = parser.parse_args()
    main(args.input, args.output)

###
#
# 依赖 zbarimg
# Windows:https://zbar.sourceforge.net/
# Linux:https://github.com/mchehab/zbar
#
###
