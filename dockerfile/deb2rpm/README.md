# deb2rpm (Docker)

在 Docker 容器中将 `.deb` 包转换为 `.rpm` 包。

转换脚本在镜像构建时从 <https://fx4.cn/deb2rpm> 拉取，入口脚本内联生成于镜像内。

## 目录结构

```
deb2rpm/
├── Dockerfile          # 镜像定义（内联 entrypoint，构建时拉取 deb2rpm.sh）
└── deb2rpm-docker.sh   # 本地封装：自动构建镜像并运行转换
```

## 准备工作

需要已安装 Docker。

## 方式一：使用封装脚本（推荐）

`deb2rpm-docker.sh` 会自动构建镜像（若不存在）并在容器中执行转换。

```bash
./deb2rpm-docker.sh <deb文件> <输出目录>
```

示例：

```bash
./deb2rpm-docker.sh ./example.deb ./out
```

转换完成后，`example.deb` 对应的 `.rpm` 包会生成在 `./out` 目录，且文件属主会自动修正为当前执行用户。

## 方式二：手动使用 Docker

### 1. 构建镜像

```bash
docker build -t deb2rpm:latest -f Dockerfile .
```

### 2. 运行转换

```bash
docker run --rm \
  -e "HOST_UID=$(id -u)" \
  -e "HOST_GID=$(id -g)" \
  -v "$(pwd)/example.deb:/input.deb:ro" \
  -v "$(pwd)/out:/output" \
  deb2rpm:latest \
  /input.deb /output
```

- `/input.deb`：容器内挂载的 deb 包路径（只读）。
- `/output`：容器内输出目录，转换后的 rpm 包会写入此处。
- `HOST_UID` / `HOST_GID`：用于把输出文件属主修正为宿主用户，避免产生 root 属主的文件。

## 参数说明

转换脚本 `deb2rpm.sh` 的签名为：

```
deb2rpm.sh <deb-file> <extract-dir>
```

- `deb-file`：待转换的 deb 包路径。
- `extract-dir`：临时工作目录（含提取内容、rpmbuild 产物及最终 rpm 包）。

## 注意事项

- 生成的 rpm 包默认禁用自动依赖检测（`AutoReqProv: no`）与 debuginfo 包。
- 架构会自动映射：`amd64→x86_64`、`i386→i686`、`arm64→aarch64`、`armhf→armhfp`。
- 版本号中的横杠会转换为点号以符合 RPM 规范（`Version` 不含横杠，`Release` 默认 `1`）。
