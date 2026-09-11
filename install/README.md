# 安装二进制软件

- [list.txt](list.txt)

```bash
rm -rf list.txt
for file in *.sh; do
    if [[ -f "$file" ]]; then
        title=$(grep -m1 '^# Description:' "$file" | cut -d':' -f2- | xargs)  # 提取标题
        if [[ -n "$title" ]]; then
            echo "$file  |  $title" >> list.txt
        else
            echo "$file" >> list.txt  # 处理无 description 的情况
        fi
    fi
done
```

## 脚本说明

| **标题** | **URL** | **描述** |
|:---|:---|:---|
| [**act**](./act.sh) | [https://fx4.cn/act](https://fx4.cn/act) | GitHub Action 本地构建 |
| [**aitr**](./aitr.sh) | [https://fx4.cn/aitr](https://fx4.cn/aitr) | AI 文档翻译工具 |
| [**aliyunpan**](./aliyunpan.sh) | [https://fx4.cn/aliyunpan](https://fx4.cn/aliyunpan) | 阿里网盘命令行工具 |
| [**android-studio**](./android-studio.sh) | [https://developer.android.com/studio](https://developer.android.com/studio) | Android Studio |
| [**asciinema**](./asciinema.sh) | [https://fx4.cn/asciinema](https://fx4.cn/asciinema) | 录制和直播终端会话的命令行工具 |
| [**ast-grep**](./ast-grep.sh) | [https://fx4.cn/ag](https://fx4.cn/ag) | 基于语法树的代码结构搜索、lint 与重写 CLI 工具（ast-grep） |
| [**atuin**](./atuin.sh) | [https://fx4.cn/atuin](https://fx4.cn/atuin) | Shell 历史记录管理工具 |
| [**bat**](./bat.sh) | [https://fx4.cn/bat](https://fx4.cn/bat) | 带语法高亮的 cat 增强工具 |
| [**bore**](./bore.sh) | [https://fx4.cn/bore](https://fx4.cn/bore) | 网络穿透工具 |
| [**bottom**](./bottom.sh) | [https://fx4.cn/bottom](https://fx4.cn/bottom) | 跨平台的图形化进程/系统监控工具 |
| [**chromium**](./chromium.sh) | [https://fx4.cn/chromium](https://fx4.cn/chromium) | Ungoogled Chromium |
| [**croc**](./croc.sh) | [https://fx4.cn/croc](https://fx4.cn/croc) | 文件传输工具 |
| [**delta**](./delta.sh) | [https://fx4.cn/delta](https://fx4.cn/delta) | 增强 git diff 的彩色显示工具 |
| [**difftastic**](./difftastic.sh) | [https://fx4.cn/difft](https://fx4.cn/difft) | 能理解语法的结构化 diff 工具 |
| [**direnv**](./direnv.sh) | [https://fx4.cn/direnv](https://fx4.cn/direnv) | Shell 环境变量管理工具 |
| [**dust**](./dust.sh) | [https://fx4.cn/dust](https://fx4.cn/dust) | 用 Rust 编写的更直观的磁盘占用分析（du）工具 |
| [**eza**](./eza.sh) | [https://fx4.cn/eza](https://fx4.cn/eza) | ls 的现代替代工具 |
| [**fd**](./fd.sh) | [https://fx4.cn/fd](https://fx4.cn/fd) | 简单快速的 find 替代工具 |
| [**flutter**](./flutter.sh) | [https://fx4.cn/flutter](https://fx4.cn/flutter) | 安装 Flutter SDK |
| [**frp**](./frp.sh) | [https://fx4.cn/frp](https://fx4.cn/frp) | 网络穿透工具 |
| [**gitlab-runner**](./gitlab-runner.sh) | [https://fx4.cn/gitlab-runner](https://fx4.cn/gitlab-runner) | GitLab Runner |
| [**goreleaser**](./goreleaser.sh) | [https://fx4.cn/goreleaser](https://fx4.cn/goreleaser) | Go语言程序构建工具 |
| [**hugo**](./hugo.sh) | [https://fx4.cn/hugo](https://fx4.cn/hugo) | 静态网站生成器 |
| [**jed**](./jed.sh) | [https://fx4.cn/jed](https://fx4.cn/jed) | 用 sed 语法处理 JSON 的命令行工具 |
| [**just**](./just.sh) | [https://fx4.cn/just](https://fx4.cn/just) | 构建工具 |
| [**lsd**](./lsd.sh) | [https://fx4.cn/lsd](https://fx4.cn/lsd) | 下一代 ls 命令：彩色、带图标、更现代的目录列表工具 |
| [**m3u8-downloader**](./m3u8-downloader.sh) | [https://fx4.cn/m3u8-downloader](https://fx4.cn/m3u8-downloader) | m3u8 下载器 (m3u8-downloader) |
| [**nvim**](./nvim.sh) | [https://fx4.cn/nvim](https://fx4.cn/nvim) | Neovim 编辑器 |
| [**obscura**](./obscura.sh) | [https://fx4.cn/obscura](https://fx4.cn/obscura) | 无头浏览器 (obscura) |
| [**prek**](./prek.sh) | [https://fx4.cn/prek](https://fx4.cn/prek) | Git 钩子管理工具 |
| [**procs**](./procs.sh) | [https://fx4.cn/procs](https://fx4.cn/procs) | 用 Rust 编写的现代 ps 进程查看替代工具 |
| [**protoc**](./protoc.sh) | [https://fx4.cn/protoc](https://fx4.cn/protoc) | protobuf 编译工具 |
| [**rclone**](./rclone.sh) | [https://fx4.cn/rclone](https://fx4.cn/rclone) | 安装 rclone 命令行工具 |
| [**relaydrop**](./relaydrop.sh) | [https://fx4.cn/relaydrop](https://fx4.cn/relaydrop) | 文件传输中继服务 |
| [**restic**](./restic.sh) | [https://fx4.cn/restic](https://fx4.cn/restic) | 安装 Restic 备份工具 |
| [**ripgrep**](./ripgrep.sh) | [https://fx4.cn/rg](https://fx4.cn/rg) | 极速递归搜索文件内容的正则工具，遵循 gitignore 规则 |
| [**rtk**](./rtk.sh) | [https://fx4.cn/rtk](https://fx4.cn/rtk) | 降低 LLM token 消耗的 CLI 代理工具 |
| [**shellcheck**](./shellcheck.sh) | [https://fx4.cn/shellcheck](https://fx4.cn/shellcheck) | Shell 脚本分析工具 |
| [**skim**](./skim.sh) | [https://fx4.cn/skim](https://fx4.cn/skim) | 命令行模糊查找器 |
| [**static-web-server**](./static-web-server.sh) | [https://fx4.cn/sws](https://fx4.cn/sws) | 静态网站服务器 |
| [**textadept**](./textadept.sh) | [https://fx4.cn/textadept](https://fx4.cn/textadept) | Textadept 编辑器 |
| [**ttyd**](./ttyd.sh) | [https://fx4.cn/ttyd](https://fx4.cn/ttyd) | ttyd SSH Web 终端 |
| [**vsd**](./vsd.sh) | [https://fx4.cn/vsd](https://fx4.cn/vsd) | HLS (m3u8) / DASH (mpd) 流媒体下载工具 |
| [**websocat**](./websocat.sh) | [https://fx4.cn/websocat](https://fx4.cn/websocat) | WebSocket 客户端工具，用于在终端进行 WebSocket 通信 |
| [**worktrunk**](./worktrunk.sh) | [https://fx4.cn/wt](https://fx4.cn/wt) | 管理 Git worktree 的 CLI，专为并行 AI Agent 工作流设计 |
| [**wush**](./wush.sh) | [https://fx4.cn/wush](https://fx4.cn/wush) | wush 网络穿透工具 |
| [**yq**](./yq.sh) | [https://fx4.cn/yq](https://fx4.cn/yq) | 便携式命令行 YAML/JSON/XML/CSV/TOML 等多种格式处理工具 |
| [**zed**](./zed.sh) | [https://fx4.cn/zed](https://fx4.cn/zed) | Zed 编辑器 |
| [**zoxide**](./zoxide.sh) | [https://fx4.cn/zoxide](https://fx4.cn/zoxide) | zoxide 智能 CD 命令行工具 |
