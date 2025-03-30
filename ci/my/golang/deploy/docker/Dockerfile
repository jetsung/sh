FROM golang:1.24 AS builder

ARG VERSION=dev \
    GOPROXY=https://proxy.golang.org \
    OS_MIRROR=""

WORKDIR /build
COPY . .

# RUN <<EOF

# # 设置镜像源
# if [ -n "$OS_MIRROR" ]; then
#     sed -i "s@http://deb.debian.org/debian@${OS_MIRROR}@g" /etc/apt/sources.list.d/debian.sources
# fi

# apt-get update -y
# apt-get install -y --no-install-recommends curl jq tar
# apt clean
# rm -rf /var/lib/apt/lists/*

# # 安装 just
# curl -fsSL https://s.asfd.cn/hM1Rzj | bash

# # 构建与整理
# just tidy
# mv dist/shortener public
# EOF
RUN <<EOF
mkdir -p /build/public/data
cp config/config.toml /build/public/

# 构建
go mod tidy
go generate ./...
CGO_ENABLED=0 GOFLAGS="-trimpath" go build -ldflags "-s -w" -o /build/public/shortener
EOF

FROM scratch AS prod

WORKDIR /app

COPY --from=builder /build/public/shortener /bin/shortener
COPY --from=builder /build/public/config.toml config.toml
COPY --from=builder /build/public/data data
EXPOSE 8080

ENTRYPOINT ["shortener"]
