## 构建镜像

### 环境变量配置

| 变量名 | 默认值 | 示例 | 说明 |
| --- | --- | --- | --- |
| `REGISTRIES` | | 命令执行: `base64 -w 0  ~/.docker/config.json` | 注册表登录信息 base64 编码 |
| ~~`REGISTRY_MIRROR`~~ | | `https://docker.m.daocloud.io` | Docker Hub 镜像加速地址 |
| `OS_MIRROR` | | `mirrors.cloud.tencent.com` | Alpine 操作系统镜像加速地址 |
| `GOPROXY` | | `https://goproxy.cn` | Go 模块代理地址 |

### 镜像列表

- [goreleaser](goreleaser)

## ｀Docker in Docker Service｀ 配置

### 通用方式：

直接修改 `config.toml` 文件的 `[[runners.docker.services]]` 部分，，以及 `variables` 必须设置 `DOCKER_TLS_CERTDIR: ""`。后面所有的 `.gitlab-ci.yml` 都可以使用。

```toml
concurrent = 1
check_interval = 0
connection_max_age = "15m0s"
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "vps"
  url = "https://gitlab.com"
  id = 2279
  token = "glrt-t3_xxdh3sLxT_uKXswNvxcW"
  token_obtained_at = 2025-03-14T18:30:46Z
  token_expires_at = 0001-01-01T00:00:00Z
  executor = "shell"
  [runners.cache]
    MaxUploadedArchiveSize = 0
    [runners.cache.s3]
    [runners.cache.gcs]
    [runners.cache.azure]

[[runners]]
  name = "docker"
  url = "https://gitlab.com"
  id = 2280
  token = "glrt-t3_S2EG2tBQYKJfsismyHzZ"
  token_obtained_at = 2025-03-14T18:34:57Z
  token_expires_at = 0001-01-01T00:00:00Z
  executor = "docker"
  [runners.cache]
    MaxUploadedArchiveSize = 0
    [runners.cache.s3]
    [runners.cache.gcs]
    [runners.cache.azure]
  [runners.docker]
    tls_verify = false
    image = "docker:latest"
    privileged = true
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/cache"]
    shm_size = 0
    network_mtu = 0

  [[runners.docker.services]]
    name = "docker:dind"
    # alias = "docker"
    command = ["--registry-mirror", "https://docker.m.daocloud.io" ]
    environment = ["HEALTHCHECK_TCP_PORT=2375"]
```

- 单独配置：

直接修改 `gitlab-ci.yml` 文件的 `services` 部分。必须包含 `services` 部分，以及 `variables` 必须设置 `DOCKER_TLS_CERTDIR: ""`。

```yaml
variables:
  CI_DEBUG_SERVICES: "true"
  TZ: Asia/Shanghai
  DOCKER_TLS_CERTDIR: ""

default:
  image: docker:latest
  # https://docs.gitlab.com/ci/services/
  services:
    - name: docker:dind
      variables:
        HEALTHCHECK_TCP_PORT: "2375"
      command: ["--registry-mirror", "https://docker.m.daocloud.io" ]
```
