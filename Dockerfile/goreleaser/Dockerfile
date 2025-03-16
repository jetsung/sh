FROM golang:1.24 AS builder

ARG GOPROXY=https://proxy.golang.org

RUN go install github.com/goreleaser/goreleaser/v2@latest

FROM golang:1.24 AS prod
LABEL maintainer="Jetsung Chan<i@jetsung.com>"

WORKDIR /app

COPY --from=builder /go/bin/goreleaser /usr/local/bin/goreleaser
RUN goreleaser --version
ENTRYPOINT [ "goreleaser" ]
