# deb2rpm (Docker)

在 Docker 容器中将 `.deb` 包转换为 `.rpm` 包。

转换脚本在镜像构建时从 <https://fx4.cn/deb2rpm> 拉取，入口脚本内联于镜像内。本目录不再包含本地 `Dockerfile`，直接使用已构建好的生产环境镜像。

## 目录结构

```
deb2rpm/
├── deb2rpm-docker.sh   # 本地封装：拉取（或复用）镜像并运行转换
└── README.md
```

## 准备工作

- 已安装 Docker。
- 已获取生产环境镜像（例如通过 `docker pull ghcr.io/jetsung/deb2rpm`）。镜像名可通过环境变量 `DEB2RPM_IMAGE` 覆盖。

## 使用方式

```bash
./deb2rpm-docker.sh <deb文件> <输出目录>
```

示例：

```bash
./deb2rpm-docker.sh ./example.deb ./out
```

转换完成后，`example.deb` 对应的 `.rpm` 包会生成在 `./out` 目录，且文件属主会自动修正为当前执行用户。

自定义镜像名：

```bash
DEB2RPM_IMAGE=registry.example.com/deb2rpm:1.0 ./deb2rpm-docker.sh ./example.deb ./out
```

默认镜像为 `ghcr.io/jetsung/deb2rpm`，可直接拉取：

```bash
docker pull ghcr.io/jetsung/deb2rpm
```

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
