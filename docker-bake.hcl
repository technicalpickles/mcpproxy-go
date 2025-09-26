# docker-bake.hcl
# Define a fast local dev build and a multi-arch release build.

variable "IMAGE"   { default = "mcpproxy-go" }
variable "VERSION" { default = "dev" }

# Common settings for all targets
target "app-base" {
  context    = "."
  dockerfile = "Dockerfile"

  # Link Dockerfile ARGs
  args = {
    VERSION = "${VERSION}"
  }

  labels = {
    "org.opencontainers.image.title"       = "mcpproxy-go",
    "org.opencontainers.image.version"     = "${VERSION}",
    "org.opencontainers.image.source"      = "https://github.com/technicalpickles/mcpproxy-go",
    "org.opencontainers.image.vendor"      = "technicalpickles",
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

# Local dev: single-platform and automatically loaded into Docker
# Equivalent to: docker buildx build --load ...
target "app" {
  inherits = ["app-base"]
  tags     = ["${IMAGE}:${VERSION}", "${IMAGE}:latest"]
  output   = ["type=docker"]
}

# Release: multi-arch (amd64+arm64), intended to push to registry
# Control pushing via CLI flag: --push
target "app-multi" {
  inherits  = ["app-base"]
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${IMAGE}:${VERSION}", "${IMAGE}:latest"]
}

# Convenience groups
group "dev"     { targets = ["app"] }
group "release" { targets = ["app-multi"] }

