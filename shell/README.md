# 实用的 Shell 脚本

- **设置更新源**

在每个需要更新的文件中，添加如下关于源的内容

```bash
# ORIGIN: https://myfiles.com/origin-sh.sh
```

## 脚本说明

| **推荐** | **文件名** | **标题** | **描述** |
|:---|:---|:---|:---|
| | [**`ffmpeg-dl`**](ffmpeg-dl.sh) | 通过 ffmpeg 下载 m3u8 视频 |
| | [**`docker-pull`**](docker-pull.sh) | Docker 通过加速站拉取镜像
| | [**`backup-update`**](backup-update.sh) | 更新服务器中的 Docker 镜像和备份数据
| | [**`git-qcloud`**](git-qcloud.sh) | 腾讯工峰 命令行工具
| | [**`gitlab-backup`**](gitlab-backup.sh) | GitLab 账号源码仓库备份 |
| | [**`docker-copy`**](docker-copy.sh) | 通用镜像复制脚本 |


## 脚本列表

---

### [dpkg-remove-kernel](dpkg-remove-kernel.sh)

删除多余的 Ubuntu 内核

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
curl -fsL https://framagit.org/jetsung/sh/-/raw/main/shell/desktop.sh | bash -s -- --help

# install software desktop
curl -fsL https://framagit.org/jetsung/sh/-/raw/main/shell/desktop.sh | bash -s -- --name 'application' --exec ~/myapp --icon ~/myicon.png
```

---

### [service](service.sh)

Linux 服务启动项创建（`systemd`）

```bash
# show help
curl -fsL https://framagit.org/jetsung/sh/-/raw/main/shell/service.sh | bash -s -- --help

# install service
curl -fsL https://framagit.org/jetsung/sh/-/raw/main/shell/service.sh | bash -s -- \
  --service 'service_name' \
  --exec "/usr/local/bin/myservice" \
  --workdir "/opt/myservice" \
  --desc "This is my service" \
  --restart 5 \
  --net \
  --environment "A=a1;B=b1"
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

---

### [code-mirror](code-mirror.sh)

Git 代码迁移到新托管平台

---

### [pusher](pusher.sh)

推送消息通知到钉钉、飞书、Lark

---

### [debfetch](debfetch.sh)

下载 deb 到自建的 APT 仓库，并更新仓库信息。  
参考：[https://apt.asfd.cn](https://apt.asfd.cn)

---

### [debgetsh](debgetsh.sh)

安装 APT 仓库 GPG 公钥

---

- remove_workflow_run.sh
- remove_packages_untagged.sh

---

### [xcurl](xcurl.sh)

替换脚本中的字符串为加速网址

---

### [docker-copy](docker-copy.sh)

通用镜像复制脚本

---