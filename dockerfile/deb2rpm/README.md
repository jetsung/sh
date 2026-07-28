# deb2rpm (Docker)

在 Docker 容器中将 `.deb` 包转换为 `.rpm` 包。

转换脚本在容器启动时由 **entrypoint.sh** 调用，该脚本内联于镜像内。镜像构建时从 <https://fx4.cn/deb2rpm> 拉取核心转换脚本 `deb2rpm.sh`。

## 目录结构

```
deb2rpm/
├── Dockerfile           # Docker 镜像构建文件
├── deb2rpm-docker.sh    # 本地封装：拉取（或复用）镜像并运行转换
└── README.md
```

## 准备工作

- 已安装 Docker。

## 使用方式

### 方式一：使用预构建镜像（推荐）

默认镜像为 `ghcr.io/jetsung/deb2rpm`，可直接拉取：

```bash
docker pull ghcr.io/jetsung/deb2rpm
```

然后执行转换：

```bash
./deb2rpm-docker.sh <deb文件或URL> <输出目录>
```

示例 — 本地 deb 文件：

```bash
./deb2rpm-docker.sh ./example.deb ./out
```

示例 — 远程 URL（自动下载并转换）：

```bash
./deb2rpm-docker.sh https://example.com/packages/example.deb ./out
```

转换完成后，`.rpm` 包会生成在输出目录，且文件属主会自动修正为当前执行用户。

自定义镜像名：

```bash
DEB2RPM_IMAGE=registry.example.com/deb2rpm:1.0 ./deb2rpm-docker.sh ./example.deb ./out
```

```bash
DEB2RPM_IMAGE=registry.example.com/deb2rpm:1.0 ./deb2rpm-docker.sh https://example.com/packages/example.deb ./out
```

### 方式二：本地构建镜像

在 `deb2rpm/` 目录下执行：

```bash
docker build -t deb2rpm .
```

构建完成后，使用本地镜像运行：

```bash
DEB2RPM_IMAGE=deb2rpm ./deb2rpm-docker.sh ./example.deb ./out
```

## 参数说明

转换脚本 `deb2rpm.sh` 的签名为：

```
deb2rpm.sh <deb-file> <extract-dir>
```

- `deb-file`：待转换的 deb 包路径或下载 URL（支持 `http://` / `https://` 协议，会自动下载后转换）。
- `extract-dir`：临时工作目录（含提取内容、rpmbuild 产物及最终 rpm 包）。

## 注意事项

- 生成的 rpm 包默认禁用自动依赖检测（`AutoReqProv: no`）与 debuginfo 包。
- 架构会自动映射：`amd64→x86_64`、`i386→i686`、`arm64→aarch64`、`armhf→armhfp`。
- 版本号中的横杠会转换为点号以符合 RPM 规范（`Version` 不含横杠，`Release` 默认 `1`）。
- 镜像内已预装 `dpkg`、`rpm`、`curl` 等必要工具，基于 `debian:bookworm-slim`。
