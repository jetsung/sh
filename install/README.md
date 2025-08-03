# 编译安装库和软件

1. 编译库或软件   
2. 安装二进制软件

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
| [**aliyunpan**](aliyunpan.sh) | [https://s.fx4.cn/aliyunpan](https://s.fx4.cn/aliyunpan) | 安装 aliyunpan |
| [**bore**](bore.sh) | [https://s.fx4.cn/bore](https://s.fx4.cn/bore) | 安装 bore 穿透工具 |
| [**croc**](croc.sh) | [https://s.fx4.cn/croc](https://s.fx4.cn/croc) | 安装 croc |
| [**frp**](frp.sh) | [https://s.fx4.cn/frp](https://s.fx4.cn/frp) | 安装 frp |
| [**gitlab-runner**](gitlab-runner.sh) | [https://s.fx4.cn/gitlab-runner](https://s.fx4.cn/gitlab-runner) | 安装 GitLab Runner |
| [**hugo**](hugo.sh) | [https://s.fx4.cn/hugo](https://s.fx4.cn/hugo) | 安装 hugo |
| [**just**](just.sh) | [https://s.fx4.cn/just](https://s.fx4.cn/just) | 安装 just 构建工具 |
| [**m3u8-downloader**](m3u8-downloader.sh) | [https://s.fx4.cn/m3u8-downloader](https://s.fx4.cn/m3u8-downloader) | 安装 m3u8 下载器 |
| [**nginx**](nginx.sh) |  | 安装 Nginx |
| [**php-8**](php-8.sh) |  |  |
| [**protoc**](protoc.sh) |  | 安装 protobuf |
| [**redis**](redis.sh) |  | 安装 redis |
| [**shellcheck**](shellcheck.sh) | [https://s.fx4.cn/shellcheck](https://s.fx4.cn/shellcheck) | 安装 shellcheck |
| [**static-web-server**](static-web-server.sh) | [https://s.fx4.cn/sws](https://s.fx4.cn/sws) | 安装 static-web-server |
| [**ttyd**](ttyd.sh) | [https://s.fx4.cn/ttyd](https://s.fx4.cn/ttyd) | 安装 ttyd |
| [**vsd**](vsd.sh) | [https://s.fx4.cn/vsd](https://s.fx4.cn/vsd) | 安装 m3u8 下载器 （vsd） |
| [**wush**](wush.sh) | [https://s.fx4.cn/wush](https://s.fx4.cn/wush) | 安装 wush 网络穿透工具 |
| [**zed**](zed.sh) | [https://s.fx4.cn/zed](https://s.fx4.cn/zed) | 安装 Zed 编辑器 |
