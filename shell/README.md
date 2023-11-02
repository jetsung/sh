# 一键脚本

- [一键脚本](#一键脚本)
  - [脚本列表](#脚本列表)
    - [ubuntu-remove-kernel](#ubuntu-remove-kernel)
    - [gitlab-runner](#gitlab-runner)
    - [docker-compose](#docker-compose)
    - [docker-buildx](#docker-buildx)
    - [m3u8-dl](#m3u8-dl)
    - [c2mp4](#c2mp4)
    - [acme-domain](#acme-domain)
    - [linux-upgrade-kernel](#linux-upgrade-kernel)
    - [desktop](#desktop)
    - [service](#service)
    - [fonts-install](#fonts-install)

## 脚本列表

### [ubuntu-remove-kernel](ubuntu-remove-kernel.sh)

> 一键删除多余的 Ubuntu 内核

### [gitlab-runner](gitlab-runner.sh)

> 一键安装 `gitlab-runner`  
> `bash gitlab-runner.sh`

### [docker-compose](docker-compose.sh)

> 一键安装 `docker compose v2`  
> `curl -SL xxxxxx | bash -s -- 2.2.2 https://ghproxy.com/`  
> `./docker-compose.sh 2.2.2 https://ghproxy.com`

```bash
curl -SL https://github.com/jetsung/sh-files/raw/main/sh/docker-compose.sh | bash
```

```bash
curl -SL https://jihulab.com/jetsung/sh-files/-/raw/main/sh/docker-compose.sh | bash
```

### [docker-buildx](docker-buildx.sh)

> 一键安装 `docker buildx`  
> `./docker-builex.sh 0.7.1 https://ghproxy.com`

```bash
curl -SL https://github.com/jetsung/sh-files/raw/main/sh/docker-buildx.sh | bash
```

```bash
curl -SL https://jihulab.com/jetsung/sh-files/-/raw/main/sh/docker-buildx.sh | bash
```

### [m3u8-dl](m3u8-dl.sh)

下载 .m3u8 的视频资源，并且将其合并为 mp4。

> 依赖：`ffmpeg`

### [c2mp4](c2mp4.sh)

将视频转换为 H.264 编码的 MP4 视频。

> 依赖：`ffmpeg`

### [acme-domain](acme-domain.sh)

一键创建域名 SSL 证书

> 依赖：`acme` (默认为 `docker: neilpang/acme.sh`)，`DNS` 方式

### [linux-upgrade-kernel](linux-upgrade-kernel.sh)

> 一键升级 Linux Kernel
> **目前仅在 `Deepin V23` 下测试成功**

### [desktop](desktop.sh)

> Linux 桌面快捷方式创建

```bash
curl -SL https://github.com/jetsung/sh-files/raw/main/sh/desktop.sh | bash -s -- --name 'application' --exec ~/myapp --icon ~/myicon.png
```

```bash
curl -SL https://jihulab.com/jetsung/sh-files/-/raw/main/sh/desktop.sh | bash -s -- --name 'application' --exec ~/myapp --icon ~/myicon.png
```

### [service](service.sh)

```bash
service.sh -h
```

```
Set systemd service

USAGE:
    service.sh [OPTIONS] <SUBCOMMANDS>

OPTIONS:
    -h, --help
                Print help information.

    -d, --desc
                Application description

    -e, --exec
                Application exec script

    -n, --name
                Application name
```

```bash
curl -SL https://github.com/jetsung/sh-files/raw/main/sh/service.sh | bash -s -- --name 'myservice' --exec "/usr/local/bin/myservice" --desc "This is my service"
```

```bash
curl -SL https://jihulab.com/jetsung/sh-files/-/raw/main/sh/service.sh | bash -s -- --name 'myservice' --exec "/usr/local/bin/myservice" --desc "This is my service"
```

### [fonts-install](fonts-install.sh)

安装当前目录及子目录下的字体

```bash
# 进入字体目录，执行
# 首先将 fonts-install.sh 添加到 PATH 目录下（比如: /usr/local/bin ）
sudo fonts-install.sh
```
