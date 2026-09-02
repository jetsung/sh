---
name: add-installer-script
description: 为本仓库 install/ 目录添加新的命令行工具安装脚本。当用户说"添加/新增/生成 安装脚本"、"把 XX 加到 install"、"为 https://github.com/owner/repo 写个安装脚本"时使用。会先通过 GitHub API 探测最新 release 中匹配当前平台的资产、判断其压缩类型，再生成符合本项目统一模板的 .sh 脚本。
---

为 `install/` 目录生成新的工具安装脚本。核心工具是 `scripts/create-script.sh`。

## 关键约定

用户只给一个项目地址（如 `https://github.com/rtk-ai/rtk`）时：

- **文件名**默认取仓库名 → `rtk.sh`
- **可执行文件名**默认同仓库名；若仓库名与实际命令名不同（如 `shellcheck-rs/shellcheck` 装出来的命令可能带前缀），用 `--bin-name` 指定
- **描述**：由 **AI 根据项目 URL + GitHub API 返回的仓库描述，总结一句中文**，通过 `--description` 写入头部 `# Description:`。用户若直接给了中文描述就以用户为准。脚本不会自动把英文原文写入头部，而是在探测/生成时展示仓库描述原文供 AI 参考，未给描述时打印提醒
- **代码链接（Source）**：写入头部 `# Source:`，用于链接源代码或官网 URL。默认从 GitHub 仓库自动推断 `https://github.com/<owner>/<repo>`；也可用 `--source` 显式指定；直接下载地址输入时留空
- **头部 URL 默认留空**（脚本头部 `URL:` 后不带值，不自动写入仓库地址或下载地址）——用户需要时可通过 `--url` / 环境变量 `URL` 指定，或在生成后手动回填
- **不得擅自更新 `install/README.md` 与 `install/list.txt`**——这两个文件由仓库维护者自行维护，生成脚本只负责产出 `.sh` 文件，不自动登记、不自动补行

## 标准工作流

### 第 1 步：探测，不要直接生成

先跑 `--detect-only`，把探测结果讲给用户听，确认无误再落地：

```bash
bash .agents/skills/add-installer-script/scripts/create-script.sh <owner/repo> --detect-only
```

输出示例：

```
[INFO] 工具名:   rtk
[INFO] 可执行名: rtk
[INFO] 资产文件: rtk-x86_64-unknown-linux-musl.tar.gz
[INFO] 下载地址: https://github.com/rtk-ai/rtk/releases/download/v0.47.0/...
[INFO] 文件类型: tar_gz
[INFO] 仓库描述: A Rust code toolkit...（供 AI 总结中文用）
```

**这一步会真实请求 GitHub API**，用来回答三个问题：
1. 这个仓库有没有 Linux/darwin 预编译包，匹配到的是哪一个
2. 那个包是什么压缩格式，决定后续用哪种解压逻辑
3. 仓库描述原文是什么——**AI 据此总结一句中文描述**

如果探测失败，用 `--list-assets` 把全部资产列出来，人工挑：

```bash
bash .agents/skills/add-installer-script/scripts/create-script.sh <owner/repo> --list-assets
```

### 第 2 步：生成

**先根据探测输出的仓库描述，用 AI 总结一句中文**（一句话、说清工具用途，避免空洞泛泛），再生成：

```bash
bash .agents/skills/add-installer-script/scripts/create-script.sh <owner/repo> \
    --description "快速查找文件的 find 替代工具"
```

> 示例：探测到 fd 的仓库描述 `A simple, fast and user-friendly alternative to 'find'`，AI 总结为中文 `简单快速的 find 替代工具`。

### 第 3 步：验证后落地

脚本会自动 `bash -n` 自检；发布前建议再跑一次 shellcheck：

```bash
bash -n rtk.sh
shellcheck rtk.sh
```

确认后用 `--install` 放进仓库（只移动脚本文件，**不更新** `install/list.txt` / `README.md`）：

```bash
bash .agents/skills/add-installer-script/scripts/create-script.sh <owner/repo> \
    --description "Rust 代码工具包" --install
```

`--install` 若发现目标已存在会**直接报错拒绝覆盖**，需人工确认。

> `install/README.md` 需要 `https://fx4.cn/<name>` 短链，脚本无法自动生成短链，必须手动补一行。

## 文件类型 → 解压逻辑映射

探测到资产后按后缀决定生成哪段逻辑：

| 类型标识 | 后缀 | 展开命令 | 实测样本 |
|---------|------|---------|---------|
| `tar_gz` | `.tar.gz` `.tgz` | `tar -xzf … -C extract` | `sharkdp/fd`、`rtk-ai/rtk`、`shellcheck` |
| `tar_xz` | `.tar.xz` `.txz` | `tar -xJf … -C extract` | 小体积工具 |
| `tar_bz2` | `.tar.bz2` | `tar -xjf … -C extract` | 少见 |
| `tar_zst` | `.tar.zst` | `tar --zstd -xf … -C extract` | 少见 |
| `tar` | `.tar` | `tar -xf … -C extract` | 少见 |
| `zip` | `.zip` | `unzip -q … -d extract` | `protocolbuffers/protobuf` |
| `gz_binary` | `.gz` | `gunzip -c … > raw_bin` | 单文件 gzip |
| `xz_binary` | `.xz` | `xz -dc … > raw_bin` | 单文件 xz |
| `bz2_binary` | `.bz2` | `bunzip2 -c … > raw_bin` | `restic/restic` |
| `binary` | 无后缀 | 直接下载为 `raw_bin` | 原生二进制 |

### 不猜目录结构：解压后自动定位可执行文件

`install/` 里的包结构分两类——有的顶层带版本目录（`shellcheck-v0.11.0/shellcheck`），有的直接就是裸文件（`skim`、`just`）。所以生成的脚本**不硬编码路径、也不依赖 `--strip-components`**，而是解压到 `extract/` 后依次尝试：

1. `raw_bin`（压缩二进制展开结果）
2. 当前目录下的 `$file_bin`
3. `find extract -name "$file_bin"`
4. `find extract -perm -u+x`（任意可执行文件）

都找不到就把包内文件列表打出来再退出——便于人工判断该用 `--bin-name` 指定什么名字。

最终用 `install -m 0755 <定位到的文件> /usr/local/bin/<bin-name>` 落地，一步完成复制 + 权限。

已实测通过的三种结构：顶层目录 tar.gz（shellcheck）、纯二进制（jq）、`.bz2` 压缩二进制（restic）、zip 带 `bin/`（protoc）。

## 平台匹配规则

生成的脚本在运行时自己解析平台（保持与 `install/` 现有脚本一致：`uname` 原样取值），匹配用正则的"或"集合而非单一字面量：

| 实际平台 | OS 正则 | ARCH 正则 |
|---------|--------|----------|
| Linux x86_64 | `linux` | `x86_64\|amd64\|x64` |
| Linux aarch64 | `linux` | `aarch64\|arm64\|armv8` |
| Linux armv7l | `linux` | `armv7\|armhf` |
| macOS x86_64 | `darwin\|macos\|osx\|apple` | `x86_64\|amd64\|x64` |
| macOS arm64 | `darwin\|macos\|osx\|apple` | `aarch64\|arm64\|armv8` |

挑选资产时会先排掉校验/签名文件（`.sha256` `.sha512` `.asc` `.sig` `.pem` `.json` `.txt` `.yaml` `.yml`），再**排掉包管理器格式（`.deb` `.rpm` `.apk`）**——这类格式不适合本模板的解压逻辑，优先选 tar.gz/zip/二进制等压缩包；随后按 `OS 且 ARCH` → 退化到 `仅 ARCH` 两级匹配，各取第一条。

> 例：`sharkdp/bat` 同名 release 里既有 `bat-musl_0.26.1_musl-linux-amd64.deb` 又有 `bat-v0.26.1-x86_64-unknown-linux-gnu.tar.gz`，若未排除 `.deb` 会误选前者导致解压失败。

## 命令行参数

```
create-script.sh <INPUT> [选项]

<INPUT>  ① GitHub 仓库：https://github.com/owner/repo 或 owner/repo
         ② 直接下载地址：https://example.com/tool.tar.gz

  --tool-name NAME     工具名 / 文件名（默认从仓库名或 URL 推断）
  --bin-name NAME      安装后的可执行文件名（默认同工具名）
  --description DESC   中文描述（AI 根据项目 URL + 仓库 API 描述总结的一句中文），写入脚本头部；未指定时脚本会提醒
  --source URL         源代码 / 官网地址，写入头部 `# Source:`；默认从 GitHub 仓库推断 https://github.com/owner/repo
  --url URL            强制指定下载地址（跳过 GitHub 探测）
  -o, --output FILE    输出文件名（默认 <工具名>.sh）
  --install            移入 install/ 并登记 list.txt
  --detect-only        只探测，不生成脚本
  --list-assets        列出最新 release 的全部资产
  -h, --help           帮助
```

## 生成的脚本结构

与 `install/` 现有脚本保持一致：

```bash
# 头部注释块（File / Description / Source / URL / Author / Version / 日期）
#   Description：写 AI 总结的一句中文（--description）；未指定时脚本会提醒
#   Source：源代码 / 官网 URL，默认从 GitHub 仓库推断（--source 可覆盖）；直接下载地址时留空
#   URL 默认留空（`# URL:` 后不带值），需要时用 --url / 环境变量 URL 或手动回填
# set -euo pipefail（DEBUG=1 时切 set -eux）
# CDN_URL="${CDN:-https://fastfile.asfd.cn/}"
# sudo_exec / check_is_command / check_in_china / check_remove_https / do_remove_https
########################## 以上为通用函数 #########################
# get_download_url <repo> <os_re> <arch_re>   # 按正则挑 release 资产
# download_exact                              # 下载 → 展开 → 定位 → install
# main                                        # 参数解析 → download_exact → 校验 + --help/--version
```

支持的环境变量（与仓库其它脚本一致）：`DEBUG`、`CN`、`CDN`、`URL`；命令行支持 `--url <地址>` 覆盖下载源。

## 安全处理

- 工具名/可执行名走白名单校验（只允许 `字母数字 . _ -`），含 `;`、空格等直接拒绝——它们会被写进生成的脚本
- 下载地址含单引号时拒绝生成；其余特殊字符（`&`、`?`、`#`）通过 awk **字面**替换注入并用单引号包裹，不受 sed / `${var//}` 的 `&` 语义影响
- 生成的脚本自动 `bash -n` 校验，不通过则报错退出

## 注意事项

1. **GitHub API 有速率限制**（未认证 60 次/小时）。报"无法获取 release 信息"时先怀疑限流，不要反复重试。
2. **仓库无 Linux 预编译包**时探测必然失败——这类工具（如需自行 `cargo install` / `go install` 的项目）不适合本模板，应告知用户。
3. 探测到的资产文件名与实际命令名不一致时（如资产叫 `protoc-*.zip` 但解压后是 `bin/protoc`），依赖"自动定位"兜底；若定位不准，用 `--bin-name` 明确指定。
4. 落地后**不要擅自补写** `install/README.md` 的短链行或 `install/list.txt` 条目，这两个文件由仓库维护者自行维护。
