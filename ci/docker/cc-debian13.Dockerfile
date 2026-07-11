FROM gcr.io/distroless/cc-debian13:latest
LABEL maintainer="Jetsung Chan<i@jetsung.com"

WORKDIR /app

COPY --from=builder /usr/local/cargo/bin/myapp /usr/local/bin/myapp

EXPOSE 8000

ENTRYPOINT ["myapp"]
