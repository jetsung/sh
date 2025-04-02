# Project name derived from current directory
project_name := `basename $(pwd)`

# Enable cross-platform compatibility by default
# CGO_ENABLED := "0"

# GOFLAGS := "-trimpath"

# Output directory for builds
dist_dir := "dist"

# Default task when running `just` with no arguments
default: build

# Build the Go binary
build:
    @echo "Building {{project_name}}..."
    @go mod tidy
    @go generate ./... || echo "No generate tasks found, continuing..."
    @CGO_ENABLED=0 GOFLAGS="-trimpath" go build -ldflags "-s -w" -o "{{project_name}}"
    @echo "Built {{project_name}} successfully"

# Prepare distribution folder with necessary files
tidy: build
    @echo "Tidying {{project_name}}..."
    @rm -rf "{{dist_dir}}/{{project_name}}"
    @mkdir -p "{{dist_dir}}/{{project_name}}/data"
    @cp "{{project_name}}" "{{dist_dir}}/{{project_name}}/"
    @cp -f "config/config.toml" "{{dist_dir}}/{{project_name}}/config.toml" || echo "Warning: config.toml not found"
    @cp -f "LICENSE" "{{dist_dir}}/{{project_name}}/LICENSE" || echo "Warning: LICENSE not found"
    @cp -f "README.md" "{{dist_dir}}/{{project_name}}/README.md" || echo "Warning: README.md not found"
    @echo "Tidied {{project_name}} successfully"

# Package the tidied distribution into a tarball
package: tidy
    @echo "Packaging {{project_name}}..."
    @tar -czf "{{dist_dir}}/{{project_name}}.tar.gz" -C "{{dist_dir}}/{{project_name}}" .
    @echo "Packaged {{project_name}} successfully"

# Clean up build artifacts
clean:
    @echo "Cleaning up..."
    @rm -f "{{project_name}}"
    @rm -rf "{{dist_dir}}"
    @echo "Cleaned up successfully"

## 参考：https://github.com/redis/go-redis/blob/master/Makefile
docker-start:
    @DATABASE_TYPE=sqlite docker compose --profile redis -f deploy/docker/compose.yml up -d

docker-stop:
    @DATABASE_TYPE=sqlite docker compose --profile redis -f deploy/docker/compose.yml down

test:
    just docker-start
    just test-ci
    just docker-stop

test-ci:
    @echo "test-ci"

go-mod-tidy:
    #!/bin/bash
    set -e
    find . -type f -name 'go.mod' -exec dirname {} \; | sort | while read dir; do
      echo "go mod tidy in $dir"
        (cd "$dir" && \
            go get -u ./... && \
            go mod tidy)
    done
