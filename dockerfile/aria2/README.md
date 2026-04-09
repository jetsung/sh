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
