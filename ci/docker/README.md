
## Docker 部署

### 使用预构建镜像

#### 可用镜像仓库

> **版本：** `latest`, `dev`(GHCR only), <`TAG`>

| Registry                                                                                   | Image                                                  |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------ |
| [**Docker Hub**](https://hub.docker.com/r/ORG/REPO/)                                | `ORG/REPO`                                    |
| [**GitHub Container Registry**](https://ghcr.io/ORG/REPO) | `ghcr.io/ORG/REPO`                            |
| **Tencent Cloud Container Registry（SG）**                                                       | `sgccr.ccs.tencentyun.com/ORG/REPO`             |
| **Aliyun Container Registry（GZ）**                                                              | `registry.cn-guangzhou.aliyuncs.com/ORG/REPO` |

### 使用 compose 启动

#### 默认：拉取预构建镜像

```bash
docker compose -f docker/compose.yaml up -d
```

#### 本地构建：使用 build 段

如需从本地 `docker/Dockerfile` 构建镜像运行：

```bash
docker compose -f docker/compose.yaml up -d --build
```
