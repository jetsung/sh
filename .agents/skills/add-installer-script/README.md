# add-installer-script

为 `install/` 目录添加新工具安装脚本的 SKILL。

## 解决什么问题

`install/` 里每个工具一个 `.sh`，脚本骨架高度重复（通用函数、CDN 加速、中国网络判断、release 解析），但**解压方式又各不相同**（tar.gz / tar.xz / zip / bz2 裸二进制 / 纯二进制）。手写容易漏细节，也容易被"包里到底有没有顶层目录"这种差异坑到。

本 SKILL 用一个辅助脚本解决：先用 GitHub API **真实探测**目标仓库最新 release 里匹配当前平台的资产及其压缩格式，再生成对应解压逻辑的脚本。

## 特性

- **先探测再生成** —— 真实请求 GitHub release API，确认资产存在且能匹配到当前平台
- **AI 总结中文描述** —— 探测时展示仓库描述原文，由 AI 根据项目 URL + API 描述总结一句中文，写入脚本头部 `# Description:`，不再留空
- **按格式生成解压逻辑** —— tar.gz / tar.xz / tar.bz2 / tar.zst / tar / zip / gz / xz / bz2 / 裸二进制
- **不猜目录结构** —— 解压后自动定位可执行文件，兼容"含顶层版本目录"和"包内直接是裸文件"两种打包方式
- **平台匹配用正则集合** —— 覆盖 `amd64|x86_64|x64`、`arm64|aarch64|armv8`、`darwin|macos|osx` 等命名差异
- **忠实复刻仓库模板** —— 通用函数、CDN 加速、`--url` 覆盖、`DEBUG` 模式与 `install/` 现有脚本完全一致
- **落地到 install/** —— `--install` 把脚本移入 `install/`，目标已存在则拒绝覆盖；`list.txt` / `README.md` 由仓库维护者自行维护
- **生成即可用** —— 自动 `bash -n` 自检；生成的脚本 shellcheck 零告警

## 目录结构

```
add-installer-script/
├── SKILL.md                 # 给 agent 读的工作流说明
├── README.md                # 本文件
├── scripts/
│   └── create-script.sh     # 生成器
└── examples/
    └── usage.md             # 端到端示例
```

## 快速开始

```bash
S=.agents/skills/add-installer-script/scripts/create-script.sh

# 1) 探测：看看能不能匹配到当前平台、是什么格式
bash $S rtk-ai/rtk --detect-only

# 2) 生成到当前目录
bash $S rtk-ai/rtk --description "Rust 代码工具包"

# 3) 自检
bash -n rtk.sh && shellcheck rtk.sh

# 4) 落地（移入 install/ 并登记 list.txt）
bash $S rtk-ai/rtk --description "Rust 代码工具包" --install
```

## 参数

```
create-script.sh <INPUT> [选项]

<INPUT>  GitHub 仓库（https://github.com/owner/repo 或 owner/repo）
         或直接下载地址（https://example.com/tool.tar.gz）

  --tool-name NAME     工具名 / 输出文件名（默认从仓库名或 URL 推断）
  --bin-name NAME      安装后的可执行文件名（默认同工具名）
  --description DESC   中文描述（AI 根据项目 URL + 仓库 API 描述总结的一句中文），写入脚本头部
  --url URL            强制指定下载地址，跳过 GitHub 探测
  -o, --output FILE    输出文件名（默认 <工具名>.sh）
  --install            移入 install/（不登记 list.txt）
  --detect-only        只探测，不生成
  --list-assets        列出最新 release 的全部资产
  -h, --help           帮助
```

## 探测输出示例

```
$ bash $S rtk-ai/rtk --detect-only
[INFO] 请求 GitHub API: rtk-ai/rtk
[INFO] 工具名:   rtk
[INFO] 可执行名: rtk
[INFO] 资产文件: rtk-x86_64-unknown-linux-musl.tar.gz
[INFO] 下载地址: https://github.com/rtk-ai/rtk/releases/download/v0.47.0/rtk-x86_64-unknown-linux-musl.tar.gz
[INFO] 文件类型: tar_gz
```

## 实测覆盖

| 仓库 | 匹配资产 | 类型 | 包结构 | 结果 |
|------|---------|------|--------|------|
| `rtk-ai/rtk` | `rtk-x86_64-unknown-linux-musl.tar.gz` | `tar_gz` | 含顶层目录 | 探测 + 生成通过 |
| `koalaman/shellcheck` | `shellcheck-v0.11.0.linux.x86_64.tar.gz` | `tar_gz` | 含顶层目录 | 端到端安装并运行通过 |
| `protocolbuffers/protobuf` | `protoc-36.1-linux-x86_64.zip` | `zip` | 含 `bin/` | 端到端安装并运行通过 |
| `restic/restic` | `restic_0.19.1_linux_amd64.bz2` | `bz2_binary` | 压缩裸二进制 | 端到端安装并运行通过 |
| `jqlang/jq`（纯 URL） | `jq-linux-amd64` | `binary` | 裸二进制 | 端到端安装并运行通过 |
| `sharkdp/fd` | `fd-v10.5.0-x86_64-unknown-linux-gnu.tar.gz` | `tar_gz` | — | 探测通过 |

> 探测/生成类验证均在 `uname` 为 `Linux x86_64` 的机器上完成。

## 生成的脚本长什么样

```bash
# 头部注释块
# 通用函数：sudo_exec / check_is_command / check_in_china / check_remove_https / do_remove_https
########################## 以上为通用函数 #########################

get_download_url() {   # 按 OS/ARCH 正则从 release assets 里挑包，跳过 .sha256/.asc 等
    ...
}

download_exact() {
    # 下载 → 展开到 extract/ 或 raw_bin → find 定位可执行文件 → install -m 0755
}

main() {
    # --url / $URL 覆盖 → 平台解析 → download_exact → command -v 校验 → --help/--version
}
```

## 已知限制

- `install/README.md` 里的链接是 `https://fx4.cn/<name>` 短链，需要人工创建，生成器不会代劳
- GitHub API 未认证限流 60 次/小时；密集批量添加时需注意
- 只处理**有预编译包**的项目。需要 `cargo install` / `go install` / 源码编译的工具不适用
- 生成的脚本装到 `/usr/local/bin`，与 `install/` 现有脚本保持一致
