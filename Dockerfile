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
# Runner (distroless, includes CA certs)
# ------------------------------------------------------------
FROM gcr.io/distroless/static-debian12 AS runner

WORKDIR /app
COPY --from=builder /out/mcpproxy /mcpproxy
COPY --from=builder --chown=65532:65532 /outfs/app/ /app/

# Run as non-root (65532=nobody in distroless)
USER 65532:65532

ENV HOME=/app

EXPOSE 8080
# Persist all app state under a single directory
VOLUME ["/app"]

ENTRYPOINT ["/mcpproxy"]
CMD ["serve", "--tray=false", "--listen", ":8080", "--config", "/app/config/mcp_config.json", "--data-dir", "/app/data", "--log-dir", "/app/logs"]
