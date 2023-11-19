# 一键脚本

- [一键脚本](#一键脚本)
  - [脚本列表](#脚本列表)
    - [ubuntu-remove-kernel](#ubuntu-remove-kernel)
    - [gitlab-runner](#gitlab-runner)
    - [m3u8-dl](#m3u8-dl)
    - [c2mp4](#c2mp4)
    - [linux-upgrade-kernel](#linux-upgrade-kernel)
    - [desktop](#desktop)
    - [service](#service)
    - [fonts-install](#fonts-install)
    - [delete-github-workflows-run](#delete-github-workflows-run)

## 脚本列表

### [ubuntu-remove-kernel](ubuntu-remove-kernel.sh)

> 一键删除多余的 Ubuntu 内核

### [gitlab-runner](gitlab-runner.sh)

> 一键安装 `gitlab-runner`  
> `bash gitlab-runner.sh`

### [m3u8-dl](m3u8-dl.sh)

下载 .m3u8 的视频资源，并且将其合并为 mp4。

> 依赖：`ffmpeg`

### [c2mp4](c2mp4.sh)

将视频转换为 H.264 编码的 MP4 视频。

> 依赖：`ffmpeg`

### [linux-upgrade-kernel](linux-upgrade-kernel.sh)

> 一键升级 Linux Kernel
> **目前仅在 `Deepin V23` 下测试成功**

### [desktop](desktop.sh)

> Linux 桌面快捷方式创建

```bash
curl -SL https://framagit.org/jetsung/scripts/-/raw/main/shell/desktop.sh | bash -s -- --name 'application' --exec ~/myapp --icon ~/myicon.png
```

```bash
curl -SL https://jihulab.com/jetsung/scripts/-/raw/main/shell/desktop.sh | bash -s -- --name 'application' --exec ~/myapp --icon ~/myicon.png
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
curl -SL https://framagit.org/jetsung/scripts/-/raw/main/shell/service.sh | bash -s -- --name 'myservice' --exec "/usr/local/bin/myservice" --desc "This is my service"
```

```bash
curl -SL https://jihulab.com/jetsung/scripts/-/raw/main/shell/service.sh | bash -s -- --name 'myservice' --exec "/usr/local/bin/myservice" --desc "This is my service"
```

### [fonts-install](fonts-install.sh)

安装当前目录及子目录下的字体

```bash
# 进入字体目录，执行
# 首先将 fonts-install.sh 添加到 PATH 目录下（比如: /usr/local/bin ）
sudo fonts-install.sh
```

### [delete-github-workflows-run](delete-github-workflows-run.sh)

删除 GitHub Workflows 的运行记录

```bash
# 首先安装 gh 工具，并且登录和授权。
delete-github-workflows-run.sh ORG_NAME REPO_NAME
```
