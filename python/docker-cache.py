#!/usr/bin/env python3

#============================================================
# File: docker-cache.py
# Description: Docker 镜像复制工具：本地执行或触发远程 GitHub Actions
#              docker-cache.yml 工作流复制镜像，成功后自动删除该次流水线运行
# URL: https://fx4.cn/dockercache
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-08-22
# UpdatedAt: 2026-08-22
#============================================================

"""
Docker 镜像复制工具

将 source_image 复制到 target_image，支持本地执行与触发远程 GitHub Actions
工作流两种模式，复制成功后默认自动删除该次流水线运行记录。

====================================================================
使用教程
====================================================================

【简介】
    与 .github/workflows/docker-cache.yml 工作流功能一致。
      - 本地模式：用密钥解密 target_auth_secret 得到目标注册表账号并登录，
        再执行 docker pull -> docker tag -> docker push。
      - 远程触发模式：通过 GitHub Actions API 触发远程仓库的 docker-cache.yml
        工作流，由 GitHub 托管 Runner 完成复制，成功后自动删除该次流水线运行
        （连同日志，可用 --keep-run 保留）。

【快速开始】
    # 1. 生成 target_auth_secret（只输出，不触发流水线）
    python3 scripts/docker-cache.py gen-secret --target-auth-key "你的密钥"

    # 2. 触发远程流水线复制（默认删除该次流水线运行）
    export GITHUB_TOKEN=ghp_xxx
    python3 scripts/docker-cache.py copy --source-image ghcr.io/hello/world

    # 3. 远程复制后再拉取到本地，并重命名为源镜像名，删除旧的目标镜像标签（--pull）
    python3 scripts/docker-cache.py copy \
        --repo jetsung/docker-build-sync --branch dev \
        --source-image alpine:latest --target-image jetsung/world --pull

    # 4. 本地直接复制
    python3 scripts/docker-cache.py copy \
        --source-image docker.io/library/alpine:latest \
        --target-image registry.cn-guangzhou.aliyuncs.com/jetsung/alpine:latest \
        --target-auth-secret U2FsdGVkX1... \
        --target-auth-key "你的密钥"

【工作原理】
    1. 本地模式：用密钥解密认证信息并登录目标注册表，执行
       docker pull -> docker tag -> docker push。
    2. 远程触发模式：记录触发前最新运行编号 -> POST workflow_dispatch ->
       轮询等待新运行出现并完成 -> 复制成功（conclusion=success）后删除
       整条流水线运行记录（连同日志）。

【命令行参数】
    copy       复制镜像（本地执行或触发远程工作流）
        -s, --source-image           源镜像（必填）
        -t, --target-image           目标镜像；可省略注册表域名（缺省自动组合）
        -r, --registry               目标注册表域名（默认 registry.cn-guangzhou.aliyuncs.com）
        -d, --default-target-image   默认镜像路径（默认 jetsung/myimage）
        -a, --target-auth-secret     目标注册表 auth 值经密钥加密后的结果
        -k, --target-auth-key        本地模式解密密钥
        -R, --repo                   远程仓库 owner/repo（默认 jetsung/docker-build-sync）
        -b, --branch                 触发分支（默认 main）
        -w, --workflow               工作流文件名（默认 docker-cache.yml）
        -T, --token                  GitHub Token，需具备 actions: write 权限
        -K, --keep-run               保留该次流水线运行（默认复制成功后自动删除）
        -p, --pull                   复制完成后拉取目标镜像到本地并重命名为源镜像名，删除旧的目标镜像标签

    gen-secret  生成 target_auth_secret（只输出，不触发流水线）
        -r, --registry               从 ~/.docker/config.json 读取哪个注册表
        -k, --target-auth-key        加密密钥（必填）

    doc        打印完整使用教程并退出

    config     初始化或查看 ~/.dbsrc 配置
        -i, --init    写入默认配置（已存在时需确认覆盖）
        -s, --show    显示配置内容
        -S, --set     设置单个配置项（KEY=VALUE）
        -G, --get     获取单个配置项的值

    ci         生成 docker-cache.yml 工作流模板到当前目录

【查看教程】
    运行以下命令可随时打印本教程：
        python3 scripts/docker-cache.py doc
====================================================================

以下为环境变量、配置文件与用法示例的详细说明。
参数优先级: 命令行参数 > 配置文件 ~/.dbsrc > 环境变量 > 默认值。
除 source_image 必须通过命令行传入外，其余参数均可通过 ~/.dbsrc 或环境变量设置
（配置文件键名与环境变量名一致）:
    DBS_TARGET_IMAGE         目标镜像；可省略注册表域名（缺省用 DBS_REGISTRY 补全），
                             不指定时由 DBS_REGISTRY + DBS_DEFAULT_TARGET_IMAGE + 源镜像名组合而成，
                             如 source_image=ghcr.io/hello/world 时得到
                             registry.cn-guangzhou.aliyuncs.com/jetsung/myimage:world
    DBS_TARGET_AUTH_SECRET   目标注册表 auth 值经密钥加密后的结果
    DBS_TARGET_AUTH_KEY      解密所用密钥（仅本地模式需要）
    DBS_REGISTRY             目标注册表域名（默认 registry.cn-guangzhou.aliyuncs.com，
                             可写 docker.io 等；镜像未写注册表时自动补全）
    DBS_DEFAULT_TARGET_IMAGE 未指定目标镜像时使用的默认镜像路径（不含注册表，
                             默认 jetsung/myimage）
    DBS_GITHUB_REPO          远程仓库 owner/repo（默认 jetsung/docker-build-sync，设置后进入远程触发模式）
    DBS_GITHUB_BRANCH        触发分支（默认 main）
    DBS_WORKFLOW_FILE        工作流文件名（默认 docker-cache.yml）
    DBS_KEEP_RUN            设为 1/true/yes 时保留该次流水线运行记录（默认复制成功后自动删除）
    DBS_PULL                设为 1/true/yes 时复制完成后拉取目标镜像到本地并重命名为源镜像名，删除旧的目标镜像标签
    GITHUB_TOKEN             GitHub Token，用于触发远程工作流（也可用 --token 传入）

配置文件 ~/.dbsrc（KEY=VALUE 格式，键名同环境变量名，支持 # 注释）示例:
    DBS_REGISTRY=docker.io
    DBS_DEFAULT_TARGET_IMAGE=jetsung/myimage
    DBS_GITHUB_REPO=jetsung/docker-build-sync
    DBS_GITHUB_BRANCH=main
    # DBS_KEEP_RUN=1
    GITHUB_TOKEN=ghp_xxx

用法示例（copy 本地模式，全部用命令行参数）:
    python3 scripts/docker-cache.py copy \
        --source-image docker.io/library/alpine:latest \
        --target-image ghcr.io/user/alpine:latest \
        --target-auth-secret U2FsdGVkX1... \
        --target-auth-key "你的密钥"

用法示例（copy 本地模式，参数 + 环境变量混用）:
    export DBS_TARGET_IMAGE=ghcr.io/user/alpine:latest
    export DBS_TARGET_AUTH_SECRET=U2FsdGVkX1...
    export DBS_TARGET_AUTH_KEY="你的密钥"
    python3 scripts/docker-cache.py copy --source-image docker.io/library/alpine:latest

用法示例（copy 远程触发模式，参数 + 环境变量混用）:
    export GITHUB_TOKEN=ghp_xxx
    export DBS_TARGET_AUTH_SECRET=U2FsdGVkX1...
    python3 scripts/docker-cache.py copy \
        --source-image ghcr.io/hello/world \
        --repo jetsung/docker-build-sync \
        --branch main

    未指定 --target-image 时，自动组合目标镜像
    （DBS_REGISTRY + DBS_DEFAULT_TARGET_IMAGE + 源镜像名作标签）:
        ghcr.io/hello/world -> registry.cn-guangzhou.aliyuncs.com/jetsung/myimage:world

生成 target_auth_secret（只输出，不触发流水线）:
    python3 scripts/docker-cache.py gen-secret --target-auth-key "你的密钥"
    # 从 ~/.docker/config.json 读取所有已登录注册表的 auth 并加密输出；
    # 用 --registry ghcr.io 可只生成指定注册表的结果

配置管理（~/.dbsrc）:
    # 初始化默认配置到 ~/.dbsrc（文件已存在时需二次确认是否覆盖）
    python3 scripts/docker-cache.py config --init
    # 显示当前配置内容
    python3 scripts/docker-cache.py config --show
    # 设置单个配置项（已存在则替换，文件不存在时自动创建）
    python3 scripts/docker-cache.py config --set DBS_REGISTRY=docker.io
    # 获取单个配置项的值
    python3 scripts/docker-cache.py config --get DBS_REGISTRY

生成工作流模板（当前目录）:
    # 生成 docker-cache.yml 到当前执行目录（已存在时需确认覆盖）
    python3 scripts/docker-cache.py ci
"""

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

# 禁止生成 __pycache__ 字节码缓存
sys.dont_write_bytecode = True


def decrypt_auth(secret: str, key: str) -> str:
    """使用 openssl aes-256-cbc + pbkdf2 解密 target_auth_secret，返回 auth（base64 编码的用户名:密码）。"""
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-a", "-A",
        "-pass", f"pass:{key}",
    ]
    proc = subprocess.run(
        cmd, input=secret.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "解密失败，请检查 target_auth_secret 与密钥是否一致\n"
            + proc.stderr.decode().strip()
        )
    return proc.stdout.decode()


def parse_credentials(auth: str) -> tuple[str, str]:
    """auth 是 base64 编码的 用户名:密码，解码并拆分。"""
    try:
        cred = base64.b64decode(auth.encode()).decode()
    except Exception as exc:
        raise ValueError(f"auth 值 Base64 解码失败: {exc}") from exc
    username, _, password = cred.partition(":")
    if not username or not password:
        raise ValueError("解码后的认证信息格式错误，应为 用户名:密码")
    return username, password


def extract_registry(image: str) -> str:
    """从目标镜像中提取注册表域名（第一个斜杠前的部分，如 ghcr.io/user/repo:tag -> ghcr.io）。"""
    if "/" not in image:
        raise ValueError(f"target_image 必须包含注册表地址，例如 ghcr.io/user/repo:tag，当前值: {image}")
    return image.split("/", 1)[0]


def ensure_registry(image: str, registry: str) -> str:
    """镜像路径未含注册表域名时，补全 registry 前缀（如 docker.io、registry.cn-guangzhou.aliyuncs.com）。"""
    first = image.split("/", 1)[0]
    if "." not in first and ":" not in first and first != "localhost":
        return f"{registry}/{image}"
    return image


def compose_target_image(source_image: str, registry: str, default_target_image: str) -> str:
    """组合目标镜像：取 source_image 的镜像名（最后一个斜杠后的部分，不含自带标签）作为标签，
    拼接到 DBS_REGISTRY + DBS_DEFAULT_TARGET_IMAGE 之后。"""
    name = source_image.rsplit("/", 1)[-1].split(":", 1)[0]
    if not name:
        raise ValueError(f"无法从 source_image 提取镜像名作为标签，当前值: {source_image}")
    base = ensure_registry(default_target_image, registry)
    # 去掉默认目标镜像自带标签，避免出现 image:tag1:tag2
    if "/" in base:
        dir_part, last = base.rsplit("/", 1)
        if ":" in last:
            base = f"{dir_part}/{last.split(':', 1)[0]}"
    return f"{base}:{name}"


def run_cmd(cmd: list[str]) -> None:
    """执行命令并透传输出，失败时抛出异常。"""
    proc = subprocess.run(cmd)
    if proc.returncode != 0:
        raise RuntimeError(f"命令执行失败 (exit {proc.returncode}): {' '.join(cmd)}")


def encrypt_auth(auth: str, key: str) -> str:
    """使用 openssl aes-256-cbc + pbkdf2 加密 auth（与工作流解密逻辑对应），返回 target_auth_secret。"""
    cmd = [
        "openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-a", "-A",
        "-pass", f"pass:{key}",
    ]
    proc = subprocess.run(
        cmd, input=auth.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if proc.returncode != 0:
        raise RuntimeError("加密失败: " + proc.stderr.decode().strip())
    return proc.stdout.decode().strip()


def gen_secret(registry: str, key: str) -> int:
    """从 ~/.docker/config.json 读取注册表 auth 并用密钥加密生成 target_auth_secret，只输出，不触发流水线。"""
    if not key:
        print(
            "错误: 必须提供密钥（--target-auth-key 或环境变量 DBS_TARGET_AUTH_KEY）",
            file=sys.stderr,
        )
        return 1
    if shutil.which("openssl") is None:
        print("错误: 未找到 openssl 命令", file=sys.stderr)
        return 1
    config_path = os.path.expanduser("~/.docker/config.json")
    if not os.path.isfile(config_path):
        print(f"错误: 未找到 Docker 配置文件: {config_path}", file=sys.stderr)
        return 1
    try:
        with open(config_path, encoding="utf-8") as fh:
            config = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"错误: 读取 {config_path} 失败: {exc}", file=sys.stderr)
        return 1
    auths = config.get("auths", {}) or {}
    if not auths:
        print(f"错误: {config_path} 中没有任何注册表登录信息，请先执行 docker login", file=sys.stderr)
        return 1
    if registry:
        if registry not in auths:
            print(
                f"错误: 配置中没有注册表 {registry} 的登录信息，已有: {'、'.join(sorted(auths))}",
                file=sys.stderr,
            )
            return 1
        auths = {registry: auths[registry]}
    for reg in sorted(auths):
        entry = auths[reg]
        auth = entry.get("auth") if isinstance(entry, dict) else None
        if not auth:
            print(f"错误: 注册表 {reg} 缺少 auth 字段，请重新执行 docker login", file=sys.stderr)
            continue
        try:
            secret = encrypt_auth(auth, key)
        except RuntimeError as exc:
            print(f"错误: 加密 {reg} 失败: {exc}", file=sys.stderr)
            continue
        print(f"[{reg}]")
        print(f"  target_auth_secret: {secret}")
    return 0


def load_config() -> dict[str, str]:
    """读取 ~/.dbsrc 配置文件（KEY=VALUE 格式，支持 # 注释与空行），不存在时返回空字典。"""
    config_path = os.path.expanduser("~/.dbsrc")
    config = {}
    if not os.path.isfile(config_path):
        return config
    try:
        with open(config_path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                key, _, value = line.partition("=")
                if key.strip():
                    config[key.strip()] = value.strip()
    except OSError as exc:
        print(f"警告: 读取 {config_path} 失败: {exc}", file=sys.stderr)
    return config


DEFAULT_DBSRC = """# docker-cache 配置文件（由 config --init 生成，键名同环境变量名，支持 # 注释）
# 取值优先级: 命令行参数 > ~/.dbsrc > 环境变量 > 默认值

DBS_REGISTRY=registry.cn-guangzhou.aliyuncs.com
DBS_DEFAULT_TARGET_IMAGE=jetsung/myimage
DBS_GITHUB_REPO=jetsung/docker-build-sync
DBS_GITHUB_BRANCH=main
DBS_WORKFLOW_FILE=docker-cache.yml

# 复制成功后自动删除该次流水线运行；设为 1 则保留
# DBS_KEEP_RUN=1
# 复制完成后拉取目标镜像到本地并重命名为源镜像名，删除旧的目标镜像标签；设为 1 则开启
# DBS_PULL=1

# 以下为敏感/具体值，请自行填写
# DBS_TARGET_IMAGE=
# DBS_TARGET_AUTH_SECRET=
# DBS_TARGET_AUTH_KEY=
# GITHUB_TOKEN=
"""


def config_init() -> int:
    """初始化默认配置到 ~/.dbsrc，文件已存在时需用户二次确认是否覆盖。"""
    config_path = os.path.expanduser("~/.dbsrc")
    if os.path.isfile(config_path):
        try:
            answer = input(f"配置文件 {config_path} 已存在，是否覆盖为默认值？[y/N] ").strip().lower()
        except EOFError:
            answer = "n"
        if answer not in ("y", "yes"):
            print("已取消，未修改配置文件")
            return 0
    try:
        with open(config_path, "w", encoding="utf-8") as fh:
            fh.write(DEFAULT_DBSRC)
    except OSError as exc:
        print(f"错误: 写入 {config_path} 失败: {exc}", file=sys.stderr)
        return 1
    print(f"已写入默认配置: {config_path}")
    return 0


def config_show() -> int:
    """显示 ~/.dbsrc 配置内容。"""
    config_path = os.path.expanduser("~/.dbsrc")
    if not os.path.isfile(config_path):
        print(f"未找到配置文件: {config_path}（可用 config --init 初始化）", file=sys.stderr)
        return 1
    try:
        with open(config_path, encoding="utf-8") as fh:
            print(fh.read(), end="")
    except OSError as exc:
        print(f"错误: 读取 {config_path} 失败: {exc}", file=sys.stderr)
        return 1
    return 0


def config_set(key_value: str) -> int:
    """设置 ~/.dbsrc 中单个配置项（KEY=VALUE），已存在则替换，文件不存在时自动创建。"""
    if "=" not in key_value:
        print("错误: --set 参数格式应为 KEY=VALUE，例如 DBS_REGISTRY=docker.io", file=sys.stderr)
        return 1
    key, _, value = key_value.partition("=")
    key = key.strip()
    value = value.strip()
    if not key:
        print("错误: --set 参数格式应为 KEY=VALUE，例如 DBS_REGISTRY=docker.io", file=sys.stderr)
        return 1
    config_path = os.path.expanduser("~/.dbsrc")
    lines = []
    if os.path.isfile(config_path):
        try:
            with open(config_path, encoding="utf-8") as fh:
                lines = fh.readlines()
        except OSError as exc:
            print(f"错误: 读取 {config_path} 失败: {exc}", file=sys.stderr)
            return 1
    # 替换已存在的非注释 KEY 行，否则在末尾追加
    replaced = False
    new_lines = []
    for line in lines:
        if line.strip() and not line.lstrip().startswith("#"):
            k, _, _ = line.partition("=")
            if k.strip() == key:
                new_lines.append(f"{key}={value}\n")
                replaced = True
                continue
        new_lines.append(line)
    if not replaced:
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines[-1] += "\n"
        new_lines.append(f"{key}={value}\n")
    try:
        with open(config_path, "w", encoding="utf-8") as fh:
            fh.writelines(new_lines)
    except OSError as exc:
        print(f"错误: 写入 {config_path} 失败: {exc}", file=sys.stderr)
        return 1
    print(f"已设置 {key}={value}")
    return 0


def config_get(key: str) -> int:
    """获取 ~/.dbsrc 中单个配置项的值。"""
    key = key.strip()
    if not key:
        print("错误: --get 需要指定配置项名，例如 DBS_REGISTRY", file=sys.stderr)
        return 1
    config_path = os.path.expanduser("~/.dbsrc")
    if not os.path.isfile(config_path):
        print(f"未找到配置文件: {config_path}（可用 config --init 初始化）", file=sys.stderr)
        return 1
    try:
        with open(config_path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                k, _, v = line.partition("=")
                if k.strip() == key:
                    print(v.strip())
                    return 0
    except OSError as exc:
        print(f"错误: 读取 {config_path} 失败: {exc}", file=sys.stderr)
        return 1
    print(f"配置中未找到 {key}", file=sys.stderr)
    return 1


CI_TEMPLATE = """name: Docker Cache

on:
  workflow_dispatch:
    inputs:
      source_image:
        description: '源镜像'
        required: true
        type: string
      target_image:
        description: '目标镜像（必须包含注册表域名，例如 ghcr.io/user/repo:tag）'
        required: true
        type: string
      target_auth_secret:
        description: '目标注册表账号密钥（由 config.json 中 auth 值与密钥加密后取得）'
        required: true
        type: string

permissions:
  contents: read
  packages: write

jobs:
  copy-image:
    runs-on: ubuntu-24.04
    env:
      SOURCE_IMAGE: ${{ inputs.source_image }}
      TARGET_IMAGE: ${{ inputs.target_image }}
    steps:
      - name: 解密认证信息并登录目标注册表
        env:
          TARGET_AUTH_SECRET: ${{ inputs.target_auth_secret }}
          TARGET_AUTH_KEY: ${{ secrets.TARGET_AUTH_KEY }}
        run: |
          set -euo pipefail

          # 1. 用密钥解密得到 auth（base64 编码的 username:password）
          AUTH="$(printf '%s' "$TARGET_AUTH_SECRET" | openssl enc -d -aes-256-cbc -pbkdf2 -a -A -pass "pass:$TARGET_AUTH_KEY")"

          # 2. base64 解码得到 username:password
          CRED="$(printf '%s' "$AUTH" | base64 -d)"
          USERNAME="${CRED%%:*}"
          PASSWORD="${CRED#*:}"
          if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
            echo "::error::解密或解析认证信息失败，请检查 target_auth_secret 与密钥是否一致" >&2
            exit 1
          fi

          # 3. 从目标镜像提取注册表地址（第一个斜杠前的部分，如 ghcr.io/user/repo:tag -> ghcr.io）
          if [[ "$TARGET_IMAGE" != */* ]]; then
            echo "::error::target_image 必须包含注册表地址，例如 ghcr.io/user/repo:tag" >&2
            exit 1
          fi
          REGISTRY="${TARGET_IMAGE%%/*}"

          # 4. 登录目标注册表（密码通过 stdin 传入，避免出现在进程参数中）
          printf '%s' "$PASSWORD" | docker login "$REGISTRY" --username "$USERNAME" --password-stdin

      - name: 复制镜像
        run: |
          set -euo pipefail
          echo "source-image: $SOURCE_IMAGE"
          echo "target-image: $TARGET_IMAGE"
          docker pull "$SOURCE_IMAGE"
          docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
          docker push "$TARGET_IMAGE"
"""


def ci_init() -> int:
    """生成 docker-cache.yml 工作流模板到当前执行目录，文件已存在时需确认覆盖。"""
    output = os.path.join(os.getcwd(), "docker-cache.yml")
    if os.path.exists(output):
        try:
            answer = input(f"文件 {output} 已存在，是否覆盖？[y/N] ").strip().lower()
        except EOFError:
            answer = "n"
        if answer not in ("y", "yes"):
            print("已取消，未生成文件")
            return 0
    try:
        with open(output, "w", encoding="utf-8") as fh:
            fh.write(CI_TEMPLATE)
    except OSError as exc:
        print(f"错误: 写入 {output} 失败: {exc}", file=sys.stderr)
        return 1
    print(f"已生成: {output}")
    return 0


def pick(cli: str, config: dict[str, str], env_name: str, default: str = "") -> str:
    """取值优先级: 命令行参数 > 配置文件 ~/.dbsrc > 环境变量 > 默认值。"""
    if cli:
        return cli
    if config.get(env_name):
        return config[env_name]
    return os.environ.get(env_name) or default


def truthy(value: str) -> bool:
    """判断配置值是否为真（1/true/yes/on）。"""
    return value.strip().lower() in ("1", "true", "yes", "on")


def parse_json(text: str):
    """解析 JSON 文本，失败时原样返回文本。"""
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def api_request(url: str, token: str, method: str = "GET", payload: dict = None):
    """发送 GitHub API 请求，返回 (status_code, 解析后的响应体)；网络错误返回 (0, 错误信息)。"""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "docker-cache.py",
    }
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode(errors="replace")
            return resp.status, (parse_json(body) if body else None)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        return exc.code, (parse_json(detail) if detail else None)
    except urllib.error.URLError as exc:
        return 0, str(exc.reason)


def latest_run_number(repo: str, workflow: str, token: str) -> int:
    """查询该工作流最近一次运行的 run_number，用于识别新触发的运行（无则返回 0）。"""
    url = (
        f"https://api.github.com/repos/{repo}/actions/workflows/{workflow}/runs"
        f"?event=workflow_dispatch&per_page=1"
    )
    status, body = api_request(url, token)
    if status != 200 or not body or not body.get("workflow_runs"):
        return 0
    return body["workflow_runs"][0].get("run_number", 0)


def wait_new_run(
    repo: str, workflow: str, token: str, before_number: int, timeout: int = 120
) -> int:
    """轮询等待新触发的运行出现，返回 run_id，超时返回 0。"""
    url = (
        f"https://api.github.com/repos/{repo}/actions/workflows/{workflow}/runs"
        f"?event=workflow_dispatch&per_page=10"
    )
    deadline = time.time() + timeout
    while time.time() < deadline:
        status, body = api_request(url, token)
        if status == 200 and body:
            for run in body.get("workflow_runs", []):
                if run.get("run_number", 0) > before_number:
                    return run.get("id", 0)
        time.sleep(3)
    return 0


def wait_run_complete(repo: str, run_id: int, token: str, timeout: int = 600) -> str:
    """轮询等待运行完成，返回 conclusion（success/failure/...），超时返回空字符串。"""
    url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}"
    deadline = time.time() + timeout
    while time.time() < deadline:
        status, body = api_request(url, token)
        if status == 200 and body.get("status") == "completed":
            return body.get("conclusion") or ""
        time.sleep(5)
    return ""


def delete_workflow_run(repo: str, run_id: int, token: str) -> bool:
    """删除指定运行的整条流水线记录（连同日志），成功返回 True。"""
    url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}"
    status, _ = api_request(url, token, method="DELETE")
    return status == 204


def pull_to_local(source_image: str, target_image: str) -> int:
    """复制成功后，将目标镜像拉取到本地并重命名为源镜像名（--pull），
    随后删除旧的目标镜像标签，本地只保留源镜像名。"""
    if shutil.which("docker") is None:
        print("错误: 未找到 docker 命令，请先安装 Docker", file=sys.stderr)
        return 1
    run_cmd(["docker", "pull", target_image])
    run_cmd(["docker", "tag", target_image, source_image])
    run_cmd(["docker", "rmi", target_image])
    print(f"已拉取 {target_image} 并重命名为 {source_image}，已删除旧镜像 {target_image}（本地）")
    return 0


def trigger_workflow(
    repo: str,
    branch: str,
    workflow: str,
    token: str,
    source_image: str,
    target_image: str,
    target_auth_secret: str,
    keep_run: bool = False,
    pull: bool = False,
) -> int:
    """通过 GitHub Actions API 触发远程仓库的 workflow_dispatch 工作流，默认在复制成功后删除该次流水线运行。"""
    if "/" not in repo or repo.count("/") != 1:
        print(
            f"错误: --repo 格式应为 owner/repo，例如 jetsung/docker-build-sync，当前值: {repo}",
            file=sys.stderr,
        )
        return 1
    if not target_auth_secret:
        print(
            "错误: 缺少 target_auth_secret（--target-auth-secret 或环境变量 DBS_TARGET_AUTH_SECRET）",
            file=sys.stderr,
        )
        return 1
    if not token:
        print(
            "错误: 缺少 GitHub Token（--token 或环境变量 GITHUB_TOKEN），"
            "Token 需具备目标仓库 actions: write 权限",
            file=sys.stderr,
        )
        return 1

    print(f"repo: {repo}")
    print(f"branch: {branch}")
    print(f"workflow: {workflow}")
    print(f"source-image: {source_image}")
    print(f"target-image: {target_image}")

    # 记录触发前该工作流的最新运行编号，用于识别新触发的运行
    before_number = latest_run_number(repo, workflow, token)

    url = f"https://api.github.com/repos/{repo}/actions/workflows/{workflow}/dispatches"
    payload = {
        "ref": branch,
        "inputs": {
            "source_image": source_image,
            "target_image": target_image,
            "target_auth_secret": target_auth_secret,
        },
    }
    status, body = api_request(url, token, method="POST", payload=payload)
    if status == 0:
        print(f"错误: 无法连接 GitHub API: {body}", file=sys.stderr)
        return 1
    if status != 204:
        hints = {
            401: "Token 无效或已过期，请检查 GITHUB_TOKEN",
            403: "Token 权限不足，需要对该仓库具备 actions: write 权限",
            404: "仓库不存在或不可见、工作流文件不存在，请检查 --repo / --workflow",
            422: "请求不合法：分支不存在，或 inputs 与工作流定义不匹配",
        }
        hint = hints.get(status, f"HTTP {status}")
        print(f"错误: 触发工作流失败（{hint}）", file=sys.stderr)
        if body:
            print(body, file=sys.stderr)
        return 1

    print("已成功触发远程工作流")
    print(f"运行状态页: https://github.com/{repo}/actions/workflows/{workflow}")
    if keep_run and not pull:
        return 0

    # 默认删除流水线；--pull 时等待复制完成后拉取到本地
    if not keep_run:
        print("等待运行完成，复制成功后自动删除该次流水线...", flush=True)
    else:
        print("等待运行完成，复制成功后拉取到本地...", flush=True)
    run_id = wait_new_run(repo, workflow, token, before_number)
    if not run_id:
        print("错误: 等待运行启动超时", file=sys.stderr)
        return 1
    conclusion = wait_run_complete(repo, run_id, token)
    if not conclusion:
        print("错误: 等待运行完成超时，可稍后手动处理", file=sys.stderr)
        return 1
    if conclusion != "success":
        print(f"运行未成功（conclusion: {conclusion}），保留流水线记录供排查", file=sys.stderr)
        return 1
    if not keep_run:
        if delete_workflow_run(repo, run_id, token):
            print(f"复制成功，已删除该次流水线运行（run_id: {run_id}）")
        else:
            print("错误: 删除流水线运行失败（Token 需具备 actions: write 权限）", file=sys.stderr)
            return 1
    else:
        print(f"复制成功（run_id: {run_id}）")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Docker 镜像复制工具：本地执行或触发远程 GitHub Actions 工作流复制镜像",
    )
    sub = parser.add_subparsers(dest="command", metavar="{copy,gen-secret,doc}", required=True)

    parser_copy = sub.add_parser(
        "copy",
        help="复制镜像（本地执行或触发远程工作流，成功后默认删除该次流水线运行）",
        description="复制镜像：本地 docker pull/tag/push，或提供 --repo 后通过 GitHub Actions API "
        "触发远程工作流（参数优先级: 命令行 > ~/.dbsrc > 环境变量 > 默认值）",
    )
    parser_copy.add_argument("-s", "--source-image", help="源镜像（必填，仅支持命令行传入）")
    parser_copy.add_argument(
        "-t", "--target-image",
        help="目标镜像；可省略注册表域名（缺省用 DBS_REGISTRY 补全；缺省读取 ~/.dbsrc 或环境变量"
        "DBS_TARGET_IMAGE；不指定时用 DBS_REGISTRY + DBS_DEFAULT_TARGET_IMAGE + 源镜像名"
        "作标签组合而成）",
    )
    parser_copy.add_argument(
        "-r", "--registry",
        help="目标注册表域名，如 registry.cn-guangzhou.aliyuncs.com、docker.io"
        "（缺省读取 ~/.dbsrc 或环境变量 DBS_REGISTRY，默认 registry.cn-guangzhou.aliyuncs.com；"
        "镜像未写注册表时自动补全）",
    )
    parser_copy.add_argument(
        "-d", "--default-target-image",
        help="未指定目标镜像时使用的默认镜像路径（不含注册表，缺省读取 ~/.dbsrc 或环境变量"
        "DBS_DEFAULT_TARGET_IMAGE，默认 jetsung/myimage）",
    )
    parser_copy.add_argument(
        "-a", "--target-auth-secret",
        help="目标注册表 auth 值经密钥加密后的结果（缺省读取 ~/.dbsrc 或环境变量 DBS_TARGET_AUTH_SECRET）",
    )
    parser_copy.add_argument(
        "-k", "--target-auth-key",
        help="本地模式解密所用密钥（必填，缺省读取 ~/.dbsrc 或环境变量 DBS_TARGET_AUTH_KEY）",
    )
    parser_copy.add_argument(
        "-R", "--repo",
        help="远程仓库 owner/repo，如 jetsung/docker-build-sync；设置后改为触发其工作流"
        "而非本地执行（缺省读取 ~/.dbsrc 或环境变量 DBS_GITHUB_REPO，默认 jetsung/docker-build-sync；"
        "显式传空字符串 \"\" 可强制走本地模式）",
    )
    parser_copy.add_argument(
        "-b", "--branch",
        help="触发分支（缺省读取 ~/.dbsrc 或环境变量 DBS_GITHUB_BRANCH，默认 main）",
    )
    parser_copy.add_argument(
        "-w", "--workflow",
        help="远程工作流文件名（缺省读取 ~/.dbsrc 或环境变量 DBS_WORKFLOW_FILE，默认 docker-cache.yml）",
    )
    parser_copy.add_argument(
        "-T", "--token",
        help="GitHub Token，需具备目标仓库 actions: write 权限（缺省读取 ~/.dbsrc 或环境变量 GITHUB_TOKEN）",
    )
    parser_copy.add_argument(
        "-K", "--keep-run",
        action="store_true",
        help="保留该次流水线运行记录（默认在复制成功后自动删除；也可用 ~/.dbsrc 或环境变量"
        "DBS_KEEP_RUN=1 开启）",
    )
    parser_copy.add_argument(
        "-p", "--pull",
        action="store_true",
        help="复制完成后将目标镜像拉取到本地并重命名为源镜像名，删除旧的目标镜像标签"
        "（远程触发模式会等待复制成功后再拉取；也可用 ~/.dbsrc 或环境变量 DBS_PULL=1 开启）",
    )

    parser_gen = sub.add_parser(
        "gen-secret",
        help="生成 target_auth_secret（从 ~/.docker/config.json 读取 auth 加密，只输出不触发流水线）",
        description="从 ~/.docker/config.json 读取注册表 auth 并用密钥加密生成 target_auth_secret，"
        "只输出结果，不触发流水线。",
    )
    parser_gen.add_argument(
        "-r", "--registry",
        help="从 ~/.docker/config.json 读取哪个注册表的 auth（不传则读 ~/.dbsrc 或列出全部）",
    )
    parser_gen.add_argument(
        "-k", "--target-auth-key",
        help="加密所用密钥（必填，缺省读取 ~/.dbsrc 或环境变量 DBS_TARGET_AUTH_KEY）",
    )

    sub.add_parser(
        "doc",
        help="打印完整使用教程并退出",
        description="打印完整使用教程（无需 -h/--help）",
    )

    parser_config = sub.add_parser(
        "config",
        help="初始化或查看 ~/.dbsrc 配置",
        description="管理 ~/.dbsrc 配置文件：--init 写入默认值（已存在时需确认覆盖），--show 显示内容。",
    )
    parser_config.add_argument(
        "-i", "--init",
        action="store_true",
        help="初始化默认配置到 ~/.dbsrc（已存在时需二次确认是否覆盖）",
    )
    parser_config.add_argument(
        "-s", "--show",
        action="store_true",
        help="显示 ~/.dbsrc 配置内容",
    )
    parser_config.add_argument(
        "-S", "--set",
        metavar="KEY=VALUE",
        help="设置单个配置项，如 DBS_REGISTRY=docker.io（已存在则替换，文件不存在时自动创建）",
    )
    parser_config.add_argument(
        "-G", "--get",
        metavar="KEY",
        help="获取单个配置项的值，如 DBS_REGISTRY",
    )

    sub.add_parser(
        "ci",
        help="生成 docker-cache.yml 工作流模板到当前目录",
        description="生成 docker-cache.yml 工作流模板文件到当前执行目录（已存在时需确认覆盖）。",
    )

    args = parser.parse_args()

    # 配置来源优先级: 命令行参数 > ~/.dbsrc > 环境变量 > 默认值
    config = load_config()

    # doc 子命令：打印完整使用教程并退出
    if args.command == "doc":
        print(__doc__)
        return 0

    # config 子命令：初始化或查看 ~/.dbsrc 配置
    if args.command == "config":
        if args.init:
            return config_init()
        if args.show:
            return config_show()
        if args.set:
            return config_set(args.set)
        if args.get:
            return config_get(args.get)
        print("错误: 请指定 config --init / --show / --set KEY=VALUE / --get KEY", file=sys.stderr)
        return 1

    # ci 子命令：生成 docker-cache.yml 工作流模板到当前目录
    if args.command == "ci":
        return ci_init()

    # gen-secret 子命令：只输出加密结果，不触发流水线
    if args.command == "gen-secret":
        return gen_secret(
            args.registry or config.get("DBS_REGISTRY") or "",
            args.target_auth_key or config.get("DBS_TARGET_AUTH_KEY")
            or os.environ.get("DBS_TARGET_AUTH_KEY"),
        )

    # ---- copy 子命令 ----
    if not args.source_image:
        print("错误: 缺少 source_image（copy -s/--source-image，必填）", file=sys.stderr)
        return 1

    # 参数优先级: 命令行参数 > ~/.dbsrc > 环境变量 > 默认值
    target_image = pick(args.target_image, config, "DBS_TARGET_IMAGE")
    default_registry = pick(
        args.registry, config, "DBS_REGISTRY", "registry.cn-guangzhou.aliyuncs.com"
    )
    default_target_image = pick(
        args.default_target_image, config, "DBS_DEFAULT_TARGET_IMAGE", "jetsung/myimage"
    )
    target_auth_secret = pick(args.target_auth_secret, config, "DBS_TARGET_AUTH_SECRET")
    target_auth_key = pick(args.target_auth_key, config, "DBS_TARGET_AUTH_KEY")
    # 显式传 --repo "" 时强制本地模式；否则 命令行 > ~/.dbsrc > 环境变量 > 默认值
    if args.repo is not None:
        repo = args.repo
    else:
        repo = pick("", config, "DBS_GITHUB_REPO", "jetsung/docker-build-sync")
    branch = pick(args.branch, config, "DBS_GITHUB_BRANCH", "main")
    workflow = pick(args.workflow, config, "DBS_WORKFLOW_FILE", "docker-cache.yml")
    token = pick(args.token, config, "GITHUB_TOKEN")
    keep_run = (
        args.keep_run
        or truthy(config.get("DBS_KEEP_RUN") or "")
        or truthy(os.environ.get("DBS_KEEP_RUN") or "")
    )
    pull = (
        args.pull
        or truthy(config.get("DBS_PULL") or "")
        or truthy(os.environ.get("DBS_PULL") or "")
    )

    # 未指定目标镜像时，用 DBS_REGISTRY + DBS_DEFAULT_TARGET_IMAGE + 源镜像名（作为标签）组合；
    # 显式指定但省略注册表域名时，用 DBS_REGISTRY 补全
    if not target_image:
        try:
            target_image = compose_target_image(args.source_image, default_registry, default_target_image)
        except ValueError as exc:
            print(f"错误: {exc}", file=sys.stderr)
            return 1
        print(f"未指定 target_image，使用默认目标镜像: {target_image}")
    else:
        target_image = ensure_registry(target_image, default_registry)

    # 远程触发模式: 设置 --repo（或环境变量 DBS_GITHUB_REPO）后走 GitHub API，不依赖本地 Docker
    if repo:
        rc = trigger_workflow(
            repo, branch, workflow, token,
            args.source_image, target_image, target_auth_secret,
            keep_run, pull,
        )
        if rc != 0:
            return rc
        if pull:
            return pull_to_local(args.source_image, target_image)
        return 0

    # ---- 本地模式 ----
    missing = []
    if not target_auth_secret:
        missing.append("target_auth_secret（--target-auth-secret 或环境变量 DBS_TARGET_AUTH_SECRET）")
    if not target_auth_key:
        missing.append("target_auth_key（--target-auth-key 或环境变量 DBS_TARGET_AUTH_KEY）")
    if missing:
        print(f"错误: 缺少以下参数: {'、'.join(missing)}", file=sys.stderr)
        return 1

    if shutil.which("docker") is None:
        print("错误: 未找到 docker 命令，请先安装 Docker", file=sys.stderr)
        return 1
    if shutil.which("openssl") is None:
        print("错误: 未找到 openssl 命令", file=sys.stderr)
        return 1

    print(f"source-image: {args.source_image}")
    print(f"target-image: {target_image}")

    try:
        auth = decrypt_auth(target_auth_secret, target_auth_key)
        username, password = parse_credentials(auth)
        registry = extract_registry(target_image)
    except (RuntimeError, ValueError) as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1

    print(f"registry: {registry}")

    # 登录目标注册表（密码经 stdin 传入，避免出现在进程参数中）
    proc = subprocess.run(
        ["docker", "login", registry, "--username", username, "--password-stdin"],
        input=password.encode(),
    )
    if proc.returncode != 0:
        print(f"错误: 登录 {registry} 失败 (exit {proc.returncode})", file=sys.stderr)
        return 1

    run_cmd(["docker", "pull", args.source_image])
    run_cmd(["docker", "tag", args.source_image, target_image])
    run_cmd(["docker", "push", target_image])
    print("复制完成")
    if pull:
        return pull_to_local(args.source_image, target_image)
    return 0


if __name__ == "__main__":
    sys.exit(main())
