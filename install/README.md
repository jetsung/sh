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
| [**chromium**](./chromium.sh) | [https://fx4.cn/chromium](https://fx4.cn/chromium) | Ungoogled Chromium |
| [**m3u8-downloader**](./m3u8-downloader.sh) | [https://fx4.cn/m3u8-downloader](https://fx4.cn/m3u8-downloader) | m3u8 下载器 (m3u8-downloader) |
| [**zoxide**](./zoxide.sh) | [https://fx4.cn/zoxide](https://fx4.cn/zoxide) | zoxide 智能 CD 命令行工具 |
| [**bore**](./bore.sh) | [https://fx4.cn/bore](https://fx4.cn/bore) | 网络穿透工具 |
| [**wush**](./wush.sh) | [https://fx4.cn/wush](https://fx4.cn/wush) | wush 网络穿透工具 |
| [**gitlab-runner**](./gitlab-runner.sh) | [https://fx4.cn/gitlab-runner](https://fx4.cn/gitlab-runner) | GitLab Runner |
| [**aitr**](./aitr.sh) | [https://fx4.cn/aitr](https://fx4.cn/aitr) | AI 文档翻译工具 |
| [**protoc**](./protoc.sh) |  | protobuf 编译工具 |
| [**static-web-server**](./static-web-server.sh) | [https://fx4.cn/sws](https://fx4.cn/sws) | 静态网站服务器 |
| [**ttyd**](./ttyd.sh) | [https://fx4.cn/ttyd](https://fx4.cn/ttyd) | ttyd SSH Web 终端 |
| [**hugo**](./hugo.sh) | [https://fx4.cn/hugo](https://fx4.cn/hugo) | 静态网站生成器 |
| [**croc**](./croc.sh) | [https://fx4.cn/croc](https://fx4.cn/croc) | 文件传输工具 |
| [**act**](./act.sh) | [https://fx4.cn/act](https://fx4.cn/act) | GitHub Action 本地构建 |
| [**frp**](./frp.sh) | [https://fx4.cn/frp](https://fx4.cn/frp) | 网络穿透工具 |
| [**aliyunpan**](./aliyunpan.sh) | [https://fx4.cn/aliyunpan](https://fx4.cn/aliyunpan) | 阿里网盘命令行工具 |
| [**just**](./just.sh) | [https://fx4.cn/just](https://fx4.cn/just) | 构建工具 |
| [**skim**](./skim.sh) | [https://fx4.cn/skim](https://fx4.cn/skim) | 命令行模糊查找器 |
| [**vsd**](./vsd.sh) | [https://fx4.cn/vsd](https://fx4.cn/vsd) | m3u8 下载器 （vsd） |
| [**shellcheck**](./shellcheck.sh) | [https://fx4.cn/shellcheck](https://fx4.cn/shellcheck) | Shell 脚本分析工具 |
| [**acme-docker**](./acme-docker.sh) | [https://fx4.cn/acme](https://fx4.cn/acme) | acme docker 方式脚本 |
| [**goreleaser**](./goreleaser.sh) | [https://fx4.cn/goreleaser](https://fx4.cn/goreleaser) | Go语言程序构建工具 |
| [**atuin**](./atuin.sh) | [https://fx4.cn/atuin](https://fx4.cn/atuin) | Shell 历史记录管理工具 |
| [**zed**](./zed.sh) | [https://fx4.cn/zed](https://fx4.cn/zed) | Zed 编辑器 |
