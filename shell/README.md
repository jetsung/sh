# 一键脚本

- [脚本列表](#脚本列表)
  - [dpkg-remove-kernel](#dpkg-remove-kernel)
  - [gitlab-runner](#gitlab-runner)
  - [dl-m3u8](#dl-m3u8)
  - [video2mp4](#video2mp4)
  - [upgrade-linux-kernel](#upgrade-linux-kernel)
  - [desktop](#desktop)
  - [fonts-install](#fonts-install)
  - [delete-github-workflows-run](#delete-github-workflows-run)

## 脚本列表

---

### [dpkg-remove-kernel](dpkg-remove-kernel.sh)

删除多余的 Ubuntu 内核

---

### [gitlab-runner](gitlab-runner.sh)

> 一键安装 `gitlab-runner`  
> `bash gitlab-runner.sh`

---

### [dl-m3u8](dl-m3u8.sh)

下载 .m3u8 的视频资源，并且将其合并为 mp4。

> 依赖：`ffmpeg`

---

### [video2mp4](video2mp4.sh)

将视频转换为 H.264 编码的 MP4 视频。

> 依赖：`ffmpeg`

---

### [upgrade-linux-kernel](upgrade-linux-kernel.sh)

一键升级 Linux Kernel

> **目前仅在 `Deepin V23` 下测试成功**

---

### [desktop](desktop.sh)

Linux 桌面快捷方式创建

```bash
# show help
curl -fsL https://framagit.org/jetsung/scripts/-/raw/main/shell/desktop.sh | bash -s -- --help

# install software desktop
curl -fsL https://framagit.org/jetsung/scripts/-/raw/main/shell/desktop.sh | bash -s -- --name 'application' --exec ~/myapp --icon ~/myicon.png
```

---

### [service](service.sh)

Linux 服务启动项创建（`systemd`）

```bash
# show help
curl -fsL https://framagit.org/jetsung/scripts/-/raw/main/shell/service.sh | bash -s -- --help

# install service
curl -fsL https://framagit.org/jetsung/scripts/-/raw/main/shell/service.sh | bash -s -- --service 'service_name' --exec "/usr/local/bin/myservice" --workdir "/opt/myservice" --desc "This is my service"
```

---

### [fonts-install](fonts-install.sh)

安装当前目录及子目录下的字体

```bash
# 进入字体目录，执行
# 首先将 fonts-install.sh 添加到 PATH 目录下（比如: /usr/local/bin ）
sudo fonts-install.sh
```

---

### [delete-github-workflows-run](delete-github-workflows-run.sh)

删除 GitHub Workflows 的运行记录

```bash
# 首先安装 gh 工具，并且登录和授权。
delete-github-workflows-run.sh ORG_NAME REPO_NAME
```
