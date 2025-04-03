# Project name derived from current directory
project_name := `basename $(pwd)`

cli_name := "shorten"

# Enable cross-platform compatibility by default
# CGO_ENABLED := "0"

# GOFLAGS := "-trimpath"

# 构建产物目录
dist_dir := "dist"

# 默认任务(build)
default: build build-cli

# 构建主程序(shortener)
build:
    @echo "Building {{project_name}}..."
    @go mod tidy
    @go generate ./... || echo "No generate tasks found, continuing..."
    @CGO_ENABLED=0 GOFLAGS="-trimpath" go build -ldflags "-s -w" -o "{{project_name}}"
    @echo "Built {{project_name}} successfully"

# 构建CLI(shorten)
build-cli:
    @echo "Building {{project_name}} CLI ({{cli_name}})..."
    @go mod tidy
    @go generate ./... || echo "No generate tasks found, continuing..."
    @CGO_ENABLED=0 GOFLAGS="-trimpath" go build -ldflags "-s -w" -o "{{cli_name}}" ./cmd/shorten/
    @echo "Built {{cli_name}} successfully"

# 构建快照版本(Goreleaser)
build-snapshot:
    @echo "Building {{project_name}} snapshot..."
    @goreleaser release --snapshot --clean
    @echo "Built {{project_name}} snapshot successfully"

# 构建发布版本(Goreleaser)
build-release:
    @echo "Building {{project_name}} release..."
    @goreleaser release --clean
    @echo "Built {{project_name}} release successfully"

# 准备构建产物目录
tidy: build
    @echo "Tidying {{project_name}}..."
    @rm -rf "{{dist_dir}}/{{project_name}}"
    @mkdir -p "{{dist_dir}}/{{project_name}}/data"
    @cp "{{project_name}}" "{{dist_dir}}/{{project_name}}/"
    @cp -f "config/config.toml" "{{dist_dir}}/{{project_name}}/config.toml" || echo "Warning: config.toml not found"
    @cp -f "LICENSE" "{{dist_dir}}/{{project_name}}/LICENSE" || echo "Warning: LICENSE not found"
    @cp -f "README.md" "{{dist_dir}}/{{project_name}}/README.md" || echo "Warning: README.md not found"
    @echo "Tidied {{project_name}} successfully"

# 打包构建产物
package: tidy
    @echo "Packaging {{project_name}}..."
    @tar -czf "{{dist_dir}}/{{project_name}}.tar.gz" -C "{{dist_dir}}/{{project_name}}" .
    @echo "Packaged {{project_name}} successfully"

# 清理构建产物
clean:
    @echo "Cleaning up..."
    @rm -f "{{project_name}}"
    @rm -f "{{cli_name}}"
    @rm -rf "{{dist_dir}}"
    @echo "Cleaned up successfully"

## 参考：https://github.com/redis/go-redis/blob/master/Makefile

# 启动服务(Docker)
docker-start:
    @DATABASE_TYPE=sqlite docker compose --profile redis -f deploy/docker/compose.yml up -d

# 停止服务(Docker)
docker-stop:
    @DATABASE_TYPE=sqlite docker compose --profile redis -f deploy/docker/compose.yml down

# 测试(启动 Docker 服务)
test:
    just docker-start
    just test-ci
    just docker-stop

# 测试(CI)
test-ci:
    @echo "test-ci"

# 格式化代码
fmt:
	gofumpt -w ./
	goimports -w  -local go.dsig.cn/shortener ./

# 检查代码
lint:
    golangci-lint run --fix ./

# 整理与更新依赖
go-mod-tidy:
    #!/bin/bash
    set -e
    find . -type f -name 'go.mod' -exec dirname {} \; | sort | while read dir; do
      echo "go mod tidy in $dir"
        (cd "$dir" && \
            go get -u ./... && \
            go mod tidy)
    done
