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
        ca-certificates curl gnupg bash \
        docker.io \
        nodejs npm \
        python3 python3-pip python-is-python3 \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates \
    # Install uv/uvx (Astral) into /usr/local/bin for npx/uv workflows
    && curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
    && groupadd -g 65532 mcpproxy \
    && useradd -u 65532 -g 65532 -d /app -s /bin/bash mcpproxy \
    && mkdir -p /app \
    && chown -R 65532:65532 /app

# Install binary in PATH and app data under /app
COPY --from=builder /out/mcpproxy /usr/local/bin/mcpproxy
COPY --from=builder --chown=65532:65532 /outfs/app/ /app/

# Environment and user
ENV HOME=/app \
    PATH=/usr/local/bin:/usr/bin:/bin
USER mcpproxy
EXPOSE 8080
VOLUME ["/app"]
ENTRYPOINT ["mcpproxy"]
# NOTE: config will be at /app/config/mcp_config.json, but using --config explicitly will make it fail unless it exists which makes first setup harder
CMD ["serve", "--tray=false", "--listen", ":8080", "--data-dir", "/app/data", "--log-dir", "/app/logs"]


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

COPY --from=builder /out/mcpproxy /usr/local/bin/mcpproxy
COPY --from=builder --chown=65532:65532 /outfs/app/ /app/
WORKDIR /app

# Run as non-root (65532=nobody in distroless)
USER 65532:65532
ENV HOME=/app \
    PATH=/usr/local/bin:/usr/bin:/bin
EXPOSE 8080
VOLUME ["/app"]
ENTRYPOINT ["mcpproxy"]
# NOTE: config will be at /app/config/mcp_config.json, but using --config explicitly will make it fail unless it exists which makes first setup harder
CMD ["serve", "--tray=false", "--listen", ":8080", "--data-dir", "/app/data", "--log-dir", "/app/logs"]
