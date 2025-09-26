.PHONY: build build-slim build-full release print

# Override as needed: IMAGE=ghcr.io/you/mcpproxy VERSION=vX.Y.Z
IMAGE  ?= ghcr.io/smart-mcp-proxy/mcpproxy
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || git rev-parse --short HEAD)
GIT_SHA ?= $(shell git rev-parse HEAD)

# Build and load both slim and full locally
build:
	docker buildx bake dev \
	  --set IMAGE=$(IMAGE) \
	  --set VERSION=$(VERSION) \
	  --set GIT_SHA=$(GIT_SHA)

# Build and load only the slim image
build-slim:
	docker buildx bake app-slim \
	  --set IMAGE=$(IMAGE) \
	  --set VERSION=$(VERSION) \
	  --set GIT_SHA=$(GIT_SHA)

# Build and load only the full image
build-full:
	docker buildx bake app-full \
	  --set IMAGE=$(IMAGE) \
	  --set VERSION=$(VERSION) \
	  --set GIT_SHA=$(GIT_SHA)

# Build multi-arch for both variants and push
release:
	docker buildx bake release --push \
	  --set IMAGE=$(IMAGE) \
	  --set VERSION=$(VERSION) \
	  --set GIT_SHA=$(GIT_SHA)

# Show resolved bake plan (debug)
print:
	docker buildx bake --print
