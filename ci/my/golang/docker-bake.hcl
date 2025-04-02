## https://docs.docker.com/build/bake/
## https://docs.docker.com/reference/cli/docker/buildx/bake/#set
## https://github.com/crazy-max/buildx#remote-with-local
## https://github.com/docker/metadata-action

variable "GO_VERSION" {
  default = "1.24"
}

variable "GO_PROXY" {
    default = "https://goproxy.cn"
}

## Special target: https://github.com/docker/metadata-action#bake-definition
target "docker-metadata-action" {}

target "_image" {
    inherits = ["docker-metadata-action"]
}

target "_common" {
    labels = {
        "org.opencontainers.image.source" = "https://github.com/idevsig/shortener"
        "org.opencontainers.image.documentation" = "https://github.com/idevsig/shortener"
        "org.opencontainers.image.authors" = "Jetsung Chan<i@jetsung.com>"
    }
    context = "."
    dockerfile = "deploy/docker/Dockerfile"
    args = {
        GO_VERSION="${GO_VERSION}"
        GOPROXY = null
    }
    platforms = ["linux/amd64"]
}

target "default" {
    inherits = ["_common"]
    args = {
        GO_VERSION="${GO_VERSION}"
        GOPROXY = "https://goproxy.cn"
        OS_MIRROR = "http://mirrors.tencent.com/debian"
    }    
    tags = [
      "shortener:local",
    ]    
}

group "dev" {
  targets = ["dev-amd64", "dev-arm64"]
}

target "dev" {
    inherits = ["_common", "_image"]
}

target "dev-amd64" {
    inherits = ["_common", "_image"]
    platforms = ["linux/amd64"]
}

target "dev-arm64" {
    inherits = ["_common", "_image"]
    platforms = ["linux/arm64"]
}

group "release" {
  targets = ["release"]
}

target "release" {
    inherits = ["_common", "_image"]
    platforms = ["linux/amd64","linux/arm64"]
}
