# add-installer-script 使用示例

所有示例在本机（Linux x86_64）实测通过。输出为真实运行结果（已去掉颜色码）。

> 脚本路径缩写：`S=.agents/skills/add-installer-script/scripts/create-script.sh`

## 示例 1：先探测，再生成（推荐流程）

```bash
# 第 1 步：探测
bash $S rtk-ai/rtk --detect-only
```

真实输出：

```
[INFO] 请求 GitHub API: rtk-ai/rtk
[INFO] 工具名:   rtk
[INFO] 可执行名: rtk
[INFO] 资产文件: rtk-x86_64-unknown-linux-musl.tar.gz
[INFO] 下载地址: https://github.com/rtk-ai/rtk/releases/download/v0.47.0/rtk-x86_64-unknown-linux-musl.tar.gz
[INFO] 文件类型: tar_gz
```

确认文件类型是 `tar_gz`、匹配到当前平台后，再生成：

```bash
bash $S rtk-ai/rtk --description "Rust 代码工具包"
```

得到 `rtk.sh`。自检后落地：

```bash
bash -n rtk.sh && shellcheck rtk.sh
bash $S rtk-ai/rtk --description "Rust 代码工具包" --install
```

## 示例 2：包内含顶层版本目录（shellcheck）

`koalaman/shellcheck` 的资产 `shellcheck-v0.11.0.linux.x86_64.tar.gz` 解压后顶层带版本目录 `shellcheck-v0.11.0/`。生成器不做任何 `--strip-components` 假设，靠"自动定位"兜底。

```bash
bash $S koalaman/shellcheck --description "Shell 脚本静态分析工具"
```

真实输出：

```
[INFO] 请求 GitHub API: koalaman/shellcheck
[INFO] 工具名:   shellcheck
[INFO] 可执行名: shellcheck
[INFO] 资产文件: shellcheck-v0.11.0.linux.x86_64.tar.gz
[INFO] 下载地址: https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.gz
[INFO] 文件类型: tar_gz
[INFO] 脚本已生成: shellcheck.sh（语法校验通过）
[WARN] 下一步: bash -n shellcheck.sh && DEBUG=1 bash shellcheck.sh
```

生成的 `download_exact` 里定位逻辑是：`find extract -type f -name "shellcheck"` 命中 `extract/shellcheck-v0.11.0/shellcheck`，随后 `install -m 0755` 装到 `/usr/local/bin/shellcheck`。

## 示例 3：zip 包 + 命令名与仓库名不同（protoc）

`protocolbuffers/protobuf` 的仓库名是 `protobuf`，但安装出来的命令是 `protoc`，且 zip 解压后可执行文件在 `bin/protoc`。用 `--tool-name` 指定命令名：

```bash
bash $S protocolbuffers/protobuf --tool-name protoc --description "protobuf 编译器"
```

真实输出（节选）：

```
[INFO] 资产文件: protoc-36.1-linux-x86_64.zip
[INFO] 文件类型: zip
[INFO] 脚本已生成: protoc.sh（语法校验通过）
```

生成的脚本里 `find extract -type f -name protoc` 命中 `extract/bin/protoc`，安装到 `/usr/local/bin/protoc`。

## 示例 4：直接下载地址（jq 纯二进制）

不经过 GitHub release API，直接给一个裸二进制下载链接：

```bash
bash $S "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" \
    --tool-name jq --description "命令行 JSON 处理器"
```

资产无压缩后缀，判定为 `binary`，下载后直接落到 `raw_bin` 再安装。

## 示例 5：bz2 压缩的裸二进制（restic）

`restic/restic` 的资产是 `restic_0.19.1_linux_amd64.bz2` —— bzip2 压缩的单个二进制，不是 tar 包。生成器识别为 `bz2_binary`，展开逻辑是 `bunzip2 -c package.bin.bz2 > raw_bin`。

## 示例 6：列出全部资产

```bash
bash $S rtk-ai/rtk --list-assets
```

输出该仓库最新 release 的每一个资产（名称 + 下载地址），便于确认该挑哪个。

## 示例 7：强制指定下载地址

跳过 GitHub 探测，直接固定下载源（适合版本已在别处固定的情况）：

```bash
bash $S rtk-ai/rtk --url "https://github.com/rtk-ai/rtk/releases/download/v0.47.0/rtk-x86_64-unknown-linux-musl.tar.gz"
```

生成的脚本默认用这个 URL，但运行时仍可用命令行 `--url <地址>` 或环境变量 `URL` 覆盖。

## 环境变量

生成的安装脚本支持（与 `install/` 其它脚本一致）：

- `CN=1` —— 强制走 CDN
- `CDN=<url>` —— 自定义 CDN 前缀
- `URL=<下载地址>` —— 覆盖默认下载源
- `DEBUG=1` —— 开启 `set -eux` 调试

## 手动收尾

生成器不会代劳的两件事：

1. `install/README.md` 里补一行 `| [**name**](./name.sh) | [https://fx4.cn/name](https://fx4.cn/name) | 中文描述 |`
   （`fx4.cn` 短链需人工创建）
2. 若 `--install` 时 `install/list.txt` 已有该条目，脚本会跳过登记并提示