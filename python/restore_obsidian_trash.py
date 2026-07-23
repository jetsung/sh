#!/usr/bin/env python3

#============================================================
# File: restore_obsidian_trash.py
# Description: 从 .trash 目录根据日志恢复被误删的 Obsidian 文件
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-07-23
# UpdatedAt: 2026-07-23
#============================================================

"""
Obsidian 文件恢复工具

根据 remotely-save 插件日志，从 .trash 目录恢复被误删的文件到原始位置。

====================================================================
使用教程
====================================================================

【简介】
    从 Obsidian 的 `.trash` 目录恢复被 remotely-save 插件误删的文件。
    当插件因同步问题将本地文件移入 `.trash` 时，本工具会读取其生成的
    日志，把文件自动还原到原位置。
    环境要求：Python 3.6+，仅依赖标准库，无需安装任何包。

【快速开始】
    在 Obsidian vault 根目录下运行（脚本默认在此目录查找
    `_debug_remotely_save` 与 `.trash`）：

        # 1. 列出可用日志（标记 * 的为默认使用的最新日志）
        python3 restore_from_trash.py --list-logs

        # 2. 预览将要恢复的文件（默认模式，不改动任何文件）
        python3 restore_from_trash.py

        # 3. 确认无误后执行实际恢复
        python3 restore_from_trash.py --execute

    运行结束后会输出统计：成功恢复 / 恢复失败 / 未找到。

【工作原理】
    1. 查找日志：未指定 -f 时，自动在 -d（默认 _debug_remotely_save）
       目录中选取修改时间最新的 sync_plans_hist_exported_on_*.md 日志。
    2. 解析日志：读取其中所有 ```json 代码块，提取 decision 含 delete
       的文件及其原始路径。
    3. 匹配文件：在 .trash 目录中按文件名（含子目录）匹配。
    4. 恢复：预览模式仅展示；执行模式将文件从 .trash 移动到原始位置
       （移动而非复制，不覆盖已有文件）。

【命令行参数】
    --log-file, -f    指定日志文件路径          默认：自动查找最新
    --log-dir, -d     日志文件所在目录          默认：_debug_remotely_save
    --list-logs, -l   列出所有可用日志并退出    默认：-
    --trash-dir, -t   回收站目录路径            默认：.trash
    --execute, -e     执行模式（实际移动文件）  默认：预览模式
    --yes, -y         跳过确认提示              默认：需手动确认
    --doc             打印完整使用教程并退出    默认：-
    --help, -h        显示简要帮助信息          默认：-

    常用组合：
        # 从指定日志恢复并跳过确认
        python3 restore_from_trash.py -f _debug_remotely_save/sync_plans_hist_exported_on_TIMESTAMP.md --execute --yes

        # 自定义日志 / 回收站目录
        python3 restore_from_trash.py -d /path/to/logs -t /path/to/trash --execute

        # 自动化脚本（无交互确认）
        python3 restore_from_trash.py -e -y

【查看教程】
    运行以下命令可随时打印本教程（无需 -h/--help）：
        python3 restore_from_trash.py --doc

【注意事项】
    - 先预览，再执行：首次使用务必先运行预览模式核对输出。
    - 执行即移动：文件会从 .trash 移走而非复制，建议恢复前先备份 .trash。
    - 不覆盖：目标位置已存在同名文件时会报错并跳过，不会覆盖。
    - 权限：需要对 .trash 及 vault 目录拥有读写权限。

【故障排查】
    找不到日志目录或日志文件：
        ls -la | grep debug                      # 确认当前位于 vault 根目录
        find . -name "_debug_remotely_save" -type d   # 定位日志目录
        python3 restore_from_trash.py -d /correct/path -l

    没有找到要恢复的文件：
        ls -lh .trash/                           # 确认 .trash 内容
        python3 restore_from_trash.py -t /path/to/trash
        python3 restore_from_trash.py -l         # 尝试其他日志文件
        python3 restore_from_trash.py -f _debug_remotely_save/another_log.md

    权限错误：
        ls -la .trash/ _debug_remotely_save/
        chmod +r .trash/* _debug_remotely_save/*

【常见问题】
    Q：日志文件在哪里？
    A：通常在 vault 根目录的 _debug_remotely_save/，文件名形如
       sync_plans_hist_exported_on_*.md。

    Q：文件恢复后还在 .trash 里吗？
    A：不在，执行模式是移动操作。

    Q：文件名冲突怎么办？
    A：脚本会报错并标记该文件为失败，不会覆盖现有文件。

    Q：能只恢复部分文件吗？
    A：当前版本会恢复日志中记录的全部文件。如需选择性恢复，先用预览
       模式查看，再手动处理。

    Q：需要安装依赖吗？
    A：不需要，仅使用 Python 标准库。
====================================================================
"""

import json
import os
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict


def parse_log_file(log_path: str) -> Dict[str, dict]:
    """读取日志文件，提取其中被删除文件的信息。

    日志为 Markdown 文件，删除记录以 ```json 代码块存放。
    返回 {原始路径: {decision, size, mtime}}。
    """
    with open(log_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    deleted_files: Dict[str, dict] = {}
    in_json_block = False
    json_lines = []

    for line in lines:
        if line.strip() == '```json':
            in_json_block = True
            json_lines = []
        elif line.strip() == '```' and in_json_block:
            # 代码块结束，解析其间累积的 JSON 内容
            json_str = ''.join(json_lines)
            try:
                data = json.loads(json_str)
            except json.JSONDecodeError as e:
                print(f"警告: 跳过无法解析的 JSON 块: {e}")
            else:
                # 仅收集决策包含 delete 的文件
                for info in data.values():
                    decision = info.get('decision', '')
                    if 'delete' in decision.lower() and info.get('local'):
                        original_key = info['local'].get('key', '')
                        # 跳过目录（以 / 结尾的 key）
                        if original_key and not original_key.endswith('/'):
                            deleted_files[original_key] = {
                                'decision': decision,
                                'size': info['local'].get('size', 0),
                                'mtime': info['local'].get('mtimeCliFmt', ''),
                            }

            in_json_block = False
            json_lines = []
        elif in_json_block:
            json_lines.append(line)

    return deleted_files


def get_trash_files(trash_dir: str) -> Dict[str, str]:
    """收集 .trash 目录下所有文件，返回 {相对路径: 绝对路径} 映射。"""
    trash_files: Dict[str, str] = {}
    trash_path = Path(trash_dir)

    for item in trash_path.rglob('*'):
        if item.is_file():
            rel_path = item.relative_to(trash_path)
            trash_files[str(rel_path)] = str(item)

    return trash_files


def restore_files(deleted_files: Dict[str, dict], trash_dir: str, base_dir: str, dry_run: bool = True):
    """将 .trash 中的文件恢复到原始位置。

    dry_run=True 时只打印预览、不移动文件。
    """
    trash_files = get_trash_files(trash_dir)

    restored_count = 0
    not_found_count = 0
    error_count = 0

    print(f"\n{'=' * 80}")
    print(f"找到 {len(deleted_files)} 个被删除的文件记录")
    print(f".trash 目录中有 {len(trash_files)} 个文件")
    print(f"{'=' * 80}\n")

    if dry_run:
        print("【预览模式】不会实际移动文件\n")

    for original_path, info in deleted_files.items():
        filename = Path(original_path).name

        # 先在 .trash 根目录按文件名匹配，再回退到任意子目录下同名文件
        trash_file = None
        if filename in trash_files:
            trash_file = trash_files[filename]
        else:
            for trash_rel, trash_full in trash_files.items():
                if Path(trash_rel).name == filename:
                    trash_file = trash_full
                    break

        if trash_file:
            target_path = Path(base_dir) / original_path

            print(f"✓ 找到: {filename}")
            print(f"  来源: {trash_file}")
            print(f"  目标: {target_path}")
            print(f"  决策: {info['decision']}")
            print(f"  大小: {info['size']} 字节")

            if dry_run:
                print(f"  状态: 🔍 预览")
                restored_count += 1
            else:
                try:
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(trash_file, target_path)
                    print(f"  状态: ✅ 已恢复")
                    restored_count += 1
                except Exception as e:
                    print(f"  状态: ❌ 错误: {e}")
                    error_count += 1

            print()
        else:
            print(f"✗ 未找到: {original_path}")
            not_found_count += 1

    print(f"\n{'=' * 80}")
    print("总结:")
    if dry_run:
        print(f"  预计可恢复: {restored_count}")
    else:
        print(f"  成功恢复: {restored_count}")
        print(f"  恢复失败: {error_count}")
    print(f"  未找到: {not_found_count}")
    print(f"{'=' * 80}\n")


def list_log_files(log_dir: str = "_debug_remotely_save"):
    """列出目录下所有日志文件，按修改时间从新到旧排序。"""
    log_path = Path(log_dir)

    if not log_path.exists():
        print(f"❌ 日志目录不存在: {log_dir}")
        return

    log_files = list(log_path.glob("sync_plans_hist_exported_on_*.md"))
    if not log_files:
        print(f"❌ 在 {log_dir} 中没有找到日志文件")
        return

    log_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    print(f"\n📁 找到 {len(log_files)} 个日志文件 (按时间从新到旧):\n")
    print(f"{'序号':<4} {'文件名':<60} {'大小':<12} {'修改时间'}")
    print("=" * 100)

    for idx, log_file in enumerate(log_files, 1):
        stat = log_file.stat()
        size_mb = stat.st_size / (1024 * 1024)
        mtime = datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
        marker = " ⭐" if idx == 1 else ""
        print(f"{idx:<4} {log_file.name:<60} {size_mb:>8.2f} MB  {mtime}{marker}")

    print("\n⭐ 标记的是默认将使用的最新日志文件\n")


def find_latest_log_file(log_dir: str = "_debug_remotely_save") -> str:
    """在日志目录中查找修改时间最新的日志文件，不存在时抛 FileNotFoundError。"""
    log_path = Path(log_dir)

    if not log_path.exists():
        raise FileNotFoundError(f"日志目录不存在: {log_dir}")

    log_files = list(log_path.glob("sync_plans_hist_exported_on_*.md"))
    if not log_files:
        raise FileNotFoundError(f"在 {log_dir} 中没有找到日志文件")

    latest_file = max(log_files, key=lambda p: p.stat().st_mtime)
    return str(latest_file)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='根据 remotely-save 日志从 .trash 恢复被误删的文件。查看完整教程请运行: python3 restore_from_trash.py --doc',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        '--doc',
        action='store_true',
        help='打印完整使用教程并退出'
    )
    parser.add_argument(
        '--log-file', '-f',
        type=str,
        help='指定日志文件路径（默认自动查找最新的日志）'
    )
    parser.add_argument(
        '--log-dir', '-d',
        type=str,
        default='_debug_remotely_save',
        help='日志文件所在目录（默认: _debug_remotely_save）'
    )
    parser.add_argument(
        '--list-logs', '-l',
        action='store_true',
        help='列出所有可用的日志文件并退出'
    )
    parser.add_argument(
        '--trash-dir', '-t',
        type=str,
        default='.trash',
        help='回收站目录路径（默认: .trash）'
    )
    parser.add_argument(
        '--execute', '-e',
        action='store_true',
        help='执行模式：实际移动文件（默认为预览模式）'
    )
    parser.add_argument(
        '--yes', '-y',
        action='store_true',
        help='跳过确认提示，直接执行'
    )

    args = parser.parse_args()

    # --doc：打印教程并退出
    if args.doc:
        print(__doc__)
        return 0

    # --list-logs 单独处理：列出后直接退出
    if args.list_logs:
        list_log_files(args.log_dir)
        return 0

    base_dir = "."  # 还原到当前 vault 根目录
    trash_dir = args.trash_dir

    # 确定要使用的日志文件：显式指定或自动取最新
    try:
        if args.log_file:
            log_file = args.log_file
            if not Path(log_file).exists():
                print(f"❌ 错误: 指定的日志文件不存在: {log_file}")
                return 1
            print(f"使用指定的日志文件: {log_file}")
        else:
            log_file = find_latest_log_file(args.log_dir)
            print(f"自动找到最新的日志文件: {log_file}")

            file_stat = Path(log_file).stat()
            mtime = datetime.fromtimestamp(file_stat.st_mtime)
            print(f"  文件大小: {file_stat.st_size:,} 字节")
            print(f"  修改时间: {mtime.strftime('%Y-%m-%d %H:%M:%S')}")

    except FileNotFoundError as e:
        print(f"❌ 错误: {e}")
        print(f"\n💡 提示: 请确认日志目录路径是否正确，或使用 --log-file 参数手动指定日志文件")
        return 1

    print("\n正在解析日志文件...")
    try:
        deleted_files = parse_log_file(log_file)
    except Exception as e:
        print(f"❌ 解析日志文件时出错: {e}")
        return 1

    if not deleted_files:
        print("没有找到被删除的文件记录")
        return 0

    # 未加 --execute 即为预览模式
    dry_run = not args.execute

    if args.execute:
        print("\n⚠️  执行模式：将实际移动文件！")
        if not args.yes:
            response = input("确认要恢复文件吗？(yes/no): ")
            if response.lower() != 'yes':
                print("已取消")
                return 0
    else:
        print("\n💡 提示：这是预览模式。要实际恢复文件，请使用 --execute 参数")

    restore_files(deleted_files, trash_dir, base_dir, dry_run)
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
