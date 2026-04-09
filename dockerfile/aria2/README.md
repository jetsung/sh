# Aria2 Docker Image

这是一个基于 Alpine Linux 的轻量级 Aria2 Docker 镜像。

## 构建镜像

```bash
docker build -t aria2 .
```

## 使用方法

你可以直接运行 `aria2c` 命令：

```bash
docker run --rm aria2 --help
```

下载文件示例：

```bash
docker run --rm -v $(pwd):/data -w /data aria2 http://example.com/file.zip
```

## 运行 RPC 服务

你可以运行 aria2 作为后台 RPC 服务，允许远程管理：

```bash
docker run -d -p 6800:6800 -v $(pwd):/data --name aria2 aria2 --enable-rpc --rpc-listen-all=true --rpc-allow-origin-all=true --rpc-secret='mysecret' --max-connection-per-server=16
```

注意：请将 `mysecret` 修改为你自己的密钥。

## 使用配置文件运行

如果你想通过配置文件管理 Aria2 设置，可以将 `aria2.conf` 映射到容器内：

```bash
docker run -d -p 6800:6800 \
  -v $(pwd)/aria2.conf:/etc/aria2/aria2.conf \
  -v $(pwd)/data:/data \
  --name aria2 aria2 --conf-path=/etc/aria2/aria2.conf
```

确保 `aria2.conf` 中包含相应的 RPC 设置：

```ini
enable-rpc=true
rpc-listen-all=true
rpc-allow-origin-all=true
rpc-secret=mysecret
dir=/data
max-connection-per-server=16
```

## 使用 Docker Compose

你也可以使用 `compose.yaml` 快速部署：

```yaml
services:
  aria2:
    image: aria2
    container_name: aria2
    ports:
      - "6800:6800"
    volumes:
      - ./data:/data
      - ./aria2.conf:/etc/aria2/aria2.conf
    command: --conf-path=/etc/aria2/aria2.conf
    restart: unless-stopped
```

启动服务：

```bash
docker compose up -d
```
