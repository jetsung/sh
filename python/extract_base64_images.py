#!/usr/bin/env python3

#============================================================
# File: extract_base64_images.py
# Description: 从 Markdown 文件中提取 base64 图片并保存为本地文件
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-07-23
# UpdatedAt: 2026-07-23
#============================================================

import re
import base64
import hashlib
from pathlib import Path
import sys


def extract_base64_images(md_file_path: str, output_dir: str = None, prefix_filename: str = None) -> None:
    """
    从 Markdown 文件中提取 base64 图片。
    前缀规则：
        - 未传入 prefix_filename 时：使用实际 md 文件名的 MD5
        - 传入 prefix_filename 时：使用该文件名（stem）的 MD5 作为前缀
    """
    md_path = Path(md_file_path)
    if not md_path.exists():
        print(f"错误：文件不存在 - {md_file_path}")
        return

    # 输出目录
    if output_dir is None:
        output_dir = md_path.parent / "images"
    else:
        output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # ==================== 前缀生成逻辑 ====================
    if prefix_filename is None:
        # 默认使用当前处理的 md 文件名
        stem = md_path.stem
        print(f"使用默认前缀（当前 md 文件名）：{stem}")
    else:
        # 使用传入的“前缀文件名”计算 MD5
        prefix_path = Path(prefix_filename)
        stem = prefix_path.stem
        print(f"使用指定前缀文件名：{prefix_filename} → stem: {stem}")

    # 计算 MD5 前缀（取前12位）
    md5_hash = hashlib.md5(stem.encode('utf-8')).hexdigest()[:12]
    prefix = md5_hash
    print(f"生成 MD5 前缀: {prefix}")
    # ====================================================

    # 读取 Markdown 文件
    with open(md_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 匹配 base64 图片标签
    pattern = r'<img\s+src="data:([^;]+);base64,([^"]+)"[^>]*>'

    def replace_callback(match: re.Match) -> str:
        mime_type = match.group(1).lower()
        base64_data = match.group(2)

        # 扩展名映射
        ext_map = {
            'image/jpeg': '.jpg',
            'image/jpg': '.jpg',
            'image/png': '.png',
            'image/gif': '.gif',
            'image/webp': '.webp'
        }
        ext = ext_map.get(mime_type, '.png')

        # 生成文件名： MD5前缀_序号.ext
        existing = list(output_dir.glob(f"{prefix}_*{ext}"))
        count = len(existing) + 1
        filename = f"{prefix}_{count:03d}{ext}"
        image_path = output_dir / filename

        try:
            image_data = base64.b64decode(base64_data)
            with open(image_path, 'wb') as img_file:
                img_file.write(image_data)
            
            print(f"✓ 已保存: {filename}")
            
            relative_path = f"images/{filename}"
            return f'\n\n![{filename}]({relative_path})\n'
        
        except Exception as e:
            print(f"✗ 保存失败 {filename}: {e}")
            return match.group(0)

    # 执行替换
    new_content = re.sub(pattern, replace_callback, content, flags=re.IGNORECASE)

    # 备份
    backup_path = md_path.with_suffix('.md.bak')
    if backup_path.exists():
        backup_path.unlink()
    md_path.rename(backup_path)
    print(f"已备份原文件 → {backup_path.name}")

    # 保存新内容
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write(new_content)

    print(f"\n🎉 处理完成！")
    print(f"   Markdown 文件: {md_path}")
    print(f"   图片目录: {output_dir}")
    print(f"   使用的 stem: {stem}")
    print(f"   MD5 前缀 : {prefix}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("使用方法:")
        print("  python extract_base64_images.py <markdown.md> [output_dir] [prefix_filename]")
        print("\n示例:")
        print("  python extract_base64_images.py 1.md")
        print("  python extract_base64_images.py 1.md ./images")
        print("  python extract_base64_images.py 1.md ./images 2025-01.md")
        print("  python extract_base64_images.py 1.md ./images article-v2.md")
        sys.exit(1)

    md_file = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else None
    prefix_filename = sys.argv[3] if len(sys.argv) > 3 else None

    extract_base64_images(md_file, output_dir, prefix_filename)
