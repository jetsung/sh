# ==========================================
# 第一阶段：从官方仓库获取 Hugo
# ==========================================
FROM debian:13-slim AS hugo-provider

ARG HUGO_VERSION=""

# 1. 单独一层：安装必要的工具并清理 apt 缓存
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq gzip tar ca-certificates bash && \
    rm -rf /var/lib/apt/lists/*

# 2. 单独一层：下载、解压、安装 Hugo
# 注意：这里使用 RUN ["bash", "-c", "..."] 或者确保 heredoc 由 bash 执行
# 在 Docker BuildKit 中，<<'EOF' 默认可能使用 sh。
# 为了强制使用 bash，我们可以改变写法，或者简单地修改语法兼容 sh。
# 这里我选择修改语法以兼容 /bin/sh (dash)，这样更轻量且无需依赖 bash 特性，
# 但既然上面已经安装了 bash，我们也可以直接用 bash 执行。

# 方法 A：推荐 - 使用 bash 执行 heredoc
# 注意：Dockerfile 的 heredoc 功能 (RUN <<EOF) 在 BuildKit 中默认使用 /bin/sh。
# 要使用 bash，我们需要稍微变通一下，或者直接使用兼容 sh 的语法。

# 下面采用【兼容 POSIX sh】的写法，这样即使没有 bash 也能运行，更加健壮。
RUN <<'EOF'
    set -e

    # --- 配置变量 ---
    PKG_PREFIX="hugo_extended_withdeploy"

    # 检测操作系统 (通常为 linux)
    OS="linux"

    # 检测架构
    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            echo "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac

    echo "Detected OS: $OS, ARCH: $ARCH"

    # --- 确定 API URL ---
    if [ -n "$HUGO_VERSION" ]; then
        # 修复点：将 [[ "$HUGO_VERSION" != v* ]] 改为 case 或 grep 检查，或者简单的字符串比较
        # sh 不支持 != v* 这种通配符比较，我们用 case 或者截取第一个字符
        case "$HUGO_VERSION" in
            v*)
                # 已经是 v 开头，不做处理
                ;;
            *)
                HUGO_VERSION="v$HUGO_VERSION"
                ;;
        esac
        echo "Using specified version: $HUGO_VERSION"
        repo_api_url="https://api.github.com/repos/gohugoio/hugo/releases/tags/${HUGO_VERSION}"
    else
        echo "Fetching latest version..."
        repo_api_url="https://api.github.com/repos/gohugoio/hugo/releases/latest"
    fi

    # --- 获取下载链接 ---
    DOWNLOAD_URL=$(curl -fsSL "$repo_api_url" | jq -r --arg arch "$ARCH" --arg os "$OS" '.assets[] | select(.name | test("\($os)-\($arch).tar.gz")) | .browser_download_url' | grep -E "${PKG_PREFIX}")

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not find download URL for ${PKG_PREFIX} on ${OS}-${ARCH}"
        echo "Available assets:"
        curl -fsSL "$repo_api_url" | jq -r '.assets[].name'
        exit 1
    fi

    echo "Downloading from: $DOWNLOAD_URL"

    # --- 下载 ---
    curl -fsSL -o hugo.tar.gz "$DOWNLOAD_URL"

    # --- 解压 ---
    tar -xzf hugo.tar.gz

    # --- 安装 ---
    # 假设解压后直接生成名为 'hugo' 的二进制文件
    mv hugo /usr/local/bin/hugo

    # 赋予执行权限
    chmod +x /usr/local/bin/hugo

    # --- 验证 ---
    echo "Hugo installed successfully:"
    hugo version

    # --- 清理当前工作目录的临时文件 ---
    rm -f hugo.tar.gz
EOF

# ==========================================
# 第二阶段：构建符合 .framagit-ci.yml 环境的基础镜像
# ==========================================
FROM debian:13-slim

# 设置环境变量（参考 .framagit-ci.yml）
ENV TZ=Asia/Shanghai

ARG DEBIAN_FRONTEND=noninteractive

# 安装构建站点和部署所需的最小依赖
# 1. ca-certificates: 确保 git/npm 的 HTTPS 连接安全
# 2. git: 处理子模块 (GIT_SUBMODULE_STRATEGY: recursive)
# 3. nodejs/npm: 用于主题资源处理及部署工具 (Surge, Vercel, Netlify, Cloudflare 等)
# 4. make: 兼容 CI 中的 make 指令
# 5. bash: 脚本运行的基础 Shell
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    bash \
    git \
    nodejs \
    npm \
    make \
    && rm -rf /var/lib/apt/lists/*

# 从官方仓库阶段复制 hugo 二进制文件
COPY --from=hugo-provider /usr/local/bin/hugo /usr/local/bin/hugo

# 设置工作目录
WORKDIR /app

# 验证安装环境是否就绪
RUN hugo version && \
    node -v && \
    npm -v && \
    make --version && \
    git --version

# 默认执行命令
CMD ["hugo"]
