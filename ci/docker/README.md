
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

脚手架会自动下发 `docker/compose.yaml`（若项目 `docker/` 下已存在则跳过）。该文件为脱敏模板，
默认拉取预构建镜像，同时保留本地构建能力。

#### 默认：拉取预构建镜像

```bash
docker compose -f docker/compose.yaml up -d
```

镜像地址、服务名、端口等可通过环境变量（或 `.env`）覆盖，例如：

```bash
export __APP_IMAGE__=ghcr.io/myorg/myrepo
export __APP_PORT__=8080
docker compose -f docker/compose.yaml up -d
```

| 变量 | 说明 | 默认值 |
| ---- | ---- | ------ |
| `__APP_NAME__` | 服务名 | `APP` |
| `__APP_CONTAINER__` | 容器名 | 同服务名 |
| `__APP_HOST__` | 容器主机名 | `app` |
| `__APP_IMAGE__` | 镜像地址（不含标签） | `ghcr.io/ORG/REPO` |
| `__APP_PORT__` | 映射端口 | `80` |

> 标签固定为 `:latest`；如需其他版本，直接修改 `docker/compose.yaml` 中的 `image` 字段。

#### 本地构建：使用 build 段

如需从本地 `docker/Dockerfile` 构建镜像运行：

```bash
docker compose -f docker/compose.yaml up -d --build
```
