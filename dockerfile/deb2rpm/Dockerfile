FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        coreutils \
        curl \
        dpkg \
        findutils \
        grep \
        gzip \
        rpm \
        rpm-build \
        sed \
        tar \
    && rm -rf /var/lib/apt/lists/*

# 从远程拉取转换脚本
RUN curl -fsSL https://fx4.cn/deb2rpm -o /usr/local/bin/deb2rpm.sh \
    && chmod +x /usr/local/bin/deb2rpm.sh

# 入口脚本：调用转换脚本并修正输出文件属主
RUN <<'ENTRYPOINT_EOF'
cat > /usr/local/bin/entrypoint.sh <<'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

/usr/local/bin/deb2rpm.sh "$@"

if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
    chown -R "${HOST_UID}:${HOST_GID}" /output
fi
SCRIPT_EOF
chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT_EOF

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
