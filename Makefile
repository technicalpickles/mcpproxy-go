.PHONY: build build-slim build-full release print

# Override as needed: IMAGE=ghcr.io/you/mcpproxy VERSION=vX.Y.Z
IMAGE  ?= ghcr.io/smart-mcp-proxy/mcpproxy
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || git rev-parse --short HEAD)
GIT_SHA ?= $(shell git rev-parse HEAD)

# Optional APT proxy (e.g., http://host.docker.internal:3142)
APT_PROXY ?=

# When APT_PROXY is set, propagate build args/hosts to full targets
ifneq ($(strip $(APT_PROXY)),)
  BAKE_PROXY_FLAGS = \
    --set app-full.args.APT_PROXY=$(APT_PROXY) \
    --set app-full-multi.args.APT_PROXY=$(APT_PROXY)
endif

# Build and load both slim and full locally
build:
	# Apply args and tags per-target to avoid variable override issues
	docker buildx bake dev \
	  --set app-slim.args.VERSION=$(VERSION) \
	  --set app-slim.args.GIT_SHA=$(GIT_SHA) \
	  --set app-slim.tags=$(IMAGE):$(VERSION)-slim \
	  --set app-slim.tags=$(IMAGE):latest-slim \
	  --set app-full.args.VERSION=$(VERSION) \
	  --set app-full.args.GIT_SHA=$(GIT_SHA) \
	  --set app-full.tags=$(IMAGE):$(VERSION) \
	  --set app-full.tags=$(IMAGE):latest \
	  $(BAKE_PROXY_FLAGS)

# Build and load only the slim image
build-slim:
	docker buildx bake app-slim \
	  --set app-slim.args.VERSION=$(VERSION) \
	  --set app-slim.args.GIT_SHA=$(GIT_SHA) \
	  --set app-slim.tags=$(IMAGE):$(VERSION)-slim \
	  --set app-slim.tags=$(IMAGE):latest-slim

# Build and load only the full image
build-full:
	docker buildx bake app-full \
	  --set app-full.args.VERSION=$(VERSION) \
	  --set app-full.args.GIT_SHA=$(GIT_SHA) \
	  --set app-full.tags=$(IMAGE):$(VERSION) \
	  --set app-full.tags=$(IMAGE):latest \
	  $(BAKE_PROXY_FLAGS)

# Build multi-arch for both variants and push
release:
	docker buildx bake release --push \
	  --set app-slim-multi.args.VERSION=$(VERSION) \
	  --set app-slim-multi.args.GIT_SHA=$(GIT_SHA) \
	  --set app-slim-multi.tags=$(IMAGE):$(VERSION)-slim \
	  --set app-slim-multi.tags=$(IMAGE):latest-slim \
	  --set app-full-multi.args.VERSION=$(VERSION) \
	  --set app-full-multi.args.GIT_SHA=$(GIT_SHA) \
	  --set app-full-multi.tags=$(IMAGE):$(VERSION) \
	  --set app-full-multi.tags=$(IMAGE):latest \
	  $(BAKE_PROXY_FLAGS)

# Show resolved bake plan (debug)
print:
	docker buildx bake --print
