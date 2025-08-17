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
| [**acme-docker**](acme-docker.sh) | [https://s.fx4.cn/acme](https://s.fx4.cn/acme) | acme docker 方式脚本 |
| [**act**](act.sh) | [https://s.fx4.cn/act](https://s.fx4.cn/act) | GitHub Action 本地构建 |
| [**aliyunpan**](aliyunpan.sh) | [https://s.fx4.cn/aliyunpan](https://s.fx4.cn/aliyunpan) | aliyunpan 阿里网盘命令行工具 |
| [**bore**](bore.sh) | [https://s.fx4.cn/bore](https://s.fx4.cn/bore) | bore 网络穿透工具 |
| [**chromium**](chromium.sh) | [https://s.fx4.cn/chromium](https://s.fx4.cn/chromium) | Ungoogled Chromium |
| [**croc**](croc.sh) | [https://s.fx4.cn/croc](https://s.fx4.cn/croc) | croc 文件传输工具 |
| [**frp**](frp.sh) | [https://s.fx4.cn/frp](https://s.fx4.cn/frp) | frp 网络穿透工具 |
| [**gitlab-runner**](gitlab-runner.sh) | [https://s.fx4.cn/gitlab-runner](https://s.fx4.cn/gitlab-runner) | GitLab Runner |
| [**hugo**](hugo.sh) | [https://s.fx4.cn/hugo](https://s.fx4.cn/hugo) | hugo 静态网站生成器 |
| [**just**](just.sh) | [https://s.fx4.cn/just](https://s.fx4.cn/just) | just 构建工具 |
| [**m3u8-downloader**](m3u8-downloader.sh) | [https://s.fx4.cn/m3u8-downloader](https://s.fx4.cn/m3u8-downloader) | m3u8 下载器 (m3u8-downloader) |
| [**protoc**](protoc.sh) |  | protobuf 编译工具 |
| [**shellcheck**](shellcheck.sh) | [https://s.fx4.cn/shellcheck](https://s.fx4.cn/shellcheck) | shellcheck Shell 脚本分析工具 |
| [**skim**](skim.sh) | [https://s.fx4.cn/skim](https://s.fx4.cn/skim) | skim 命令行模糊查找器 |
| [**static-web-server**](static-web-server.sh) | [https://s.fx4.cn/sws](https://s.fx4.cn/sws) | static-web-server 静态网站服务器 |
| [**ttyd**](ttyd.sh) | [https://s.fx4.cn/ttyd](https://s.fx4.cn/ttyd) | ttyd SSH Web 终端 |
| [**vsd**](vsd.sh) | [https://s.fx4.cn/vsd](https://s.fx4.cn/vsd) | m3u8 下载器 （vsd） |
| [**wush**](wush.sh) | [https://s.fx4.cn/wush](https://s.fx4.cn/wush) | wush 网络穿透工具 |
| [**zed**](zed.sh) | [https://s.fx4.cn/zed](https://s.fx4.cn/zed) | Zed 编辑器 |
| [**zoxide**](zoxide.sh) | [https://s.fx4.cn/zoxide](https://s.fx4.cn/zoxide) | zoxide 智能 CD 命令行工具 |
