# docker-bake.hcl
# Build both slim (distroless) and full (bookworm-slim with runtimes) images.

variable "IMAGE"       { default = "ghcr.io/smart-mcp-proxy/mcpproxy" }
variable "VERSION"     { default = "dev" }
variable "GO_VERSION"  { default = "1.23" }
variable "GIT_SHA"     { default = "unknown" }

# Common settings for all targets
target "app-base" {
  context    = "."
  dockerfile = "Dockerfile"

  # Link Dockerfile ARGs
  args = {
    VERSION    = "${VERSION}"
    GO_VERSION = "${GO_VERSION}"
    GIT_SHA    = "${GIT_SHA}"
  }

  labels = {
    "org.opencontainers.image.title"       = "mcpproxy",
    "org.opencontainers.image.version"     = "${VERSION}",
    "org.opencontainers.image.source"      = "https://github.com/smart-mcp-proxy/mcpproxy-go",
    "org.opencontainers.image.vendor"      = "smart-mcp-proxy",
    "org.opencontainers.image.licenses"    = "MIT"
  }

  # Reuse layers between runs for speed
  cache-from = [
    "type=local,src=.cache/buildx"
  ]
  cache-to = [
    "type=local,dest=.cache/buildx,mode=max"
  ]
}

## Slim (distroless) targets
target "app-slim" {
  inherits = ["app-base"]
  target   = "slim"
  tags     = ["${IMAGE}:${VERSION}-slim", "${IMAGE}:latest-slim"]
  output   = ["type=docker"]
}

target "app-slim-multi" {
  inherits  = ["app-base"]
  target    = "slim"
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${IMAGE}:${VERSION}-slim", "${IMAGE}:latest-slim"]
}

## Full (bookworm-slim with runtimes) targets
target "app-full" {
  inherits = ["app-base"]
  target   = "full"
  tags     = ["${IMAGE}:${VERSION}", "${IMAGE}:latest"]
  output   = ["type=docker"]
}

target "app-full-multi" {
  inherits  = ["app-base"]
  target    = "full"
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${IMAGE}:${VERSION}", "${IMAGE}:latest"]
}

# Convenience groups
group "dev"     { targets = ["app-slim", "app-full"] }
group "release" { targets = ["app-slim-multi", "app-full-multi"] }
