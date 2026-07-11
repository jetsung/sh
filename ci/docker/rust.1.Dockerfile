FROM rust:1-trixie AS builder

WORKDIR /app

COPY . .

RUN cargo install --path .
