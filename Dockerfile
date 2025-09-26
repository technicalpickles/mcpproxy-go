# syntax=docker/dockerfile:1.7

# ------------------------------------------------------------
# Builder
# ------------------------------------------------------------
ARG GO_VERSION=1.23
FROM golang:${GO_VERSION}-alpine AS builder

WORKDIR /src

# Reproducible, portable Linux build (no tray)
ENV CGO_ENABLED=0 \
    GOFLAGS=-trimpath

# Cache dependencies in a separate layer
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Copy the rest of the source
COPY . .

# Build with module and build caches
ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -tags nogui -ldflags "-s -w -X mcpproxy-go/cmd/mcpproxy.version=${VERSION} -X main.version=${VERSION}" -o /out/mcpproxy ./cmd/mcpproxy

# Pre-create owned directories to copy into distroless under /app
RUN mkdir -p /outfs/app/config /outfs/app/data /outfs/app/logs \
    && chown -R 65532:65532 /outfs/app


# ------------------------------------------------------------
# Runner (full) - Debian bookworm-slim with runtimes and docker CLI
# Build with: --target full
# ------------------------------------------------------------
FROM debian:bookworm-slim AS full

ARG VERSION=dev
ARG GIT_SHA=unknown

LABEL org.opencontainers.image.source="https://github.com/smart-mcp-proxy/mcpproxy-go" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.description="MCPProxy full image with shells, docker CLI, Node/npm (npx), Python/pip"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        docker.io \
        nodejs npm \
        python3 python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

WORKDIR /app
COPY --from=builder /out/mcpproxy /mcpproxy
COPY --from=builder --chown=65532:65532 /outfs/app/ /app/

# Run as non-root
USER 65532:65532
ENV HOME=/app
EXPOSE 8080
VOLUME ["/app"]
ENTRYPOINT ["/mcpproxy"]
CMD ["serve", "--tray=false", "--listen", ":8080", "--config", "/app/config/mcp_config.json", "--data-dir", "/app/data", "--log-dir", "/app/logs"]


# ------------------------------------------------------------
# Runner (slim) - distroless (includes CA certs)
# Default image (last stage)
# Build with: --target slim (optional) or default
# ------------------------------------------------------------
FROM gcr.io/distroless/static-debian12 AS slim

ARG VERSION=dev
ARG GIT_SHA=unknown

LABEL org.opencontainers.image.source="https://github.com/smart-mcp-proxy/mcpproxy-go" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.description="MCPProxy slim runtime (distroless)"

WORKDIR /app
COPY --from=builder /out/mcpproxy /mcpproxy
COPY --from=builder --chown=65532:65532 /outfs/app/ /app/

# Run as non-root (65532=nobody in distroless)
USER 65532:65532
ENV HOME=/app
EXPOSE 8080
VOLUME ["/app"]
ENTRYPOINT ["/mcpproxy"]
CMD ["serve", "--tray=false", "--listen", ":8080", "--config", "/app/config/mcp_config.json", "--data-dir", "/app/data", "--log-dir", "/app/logs"]
