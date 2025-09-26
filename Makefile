.PHONY: build release print build-tags

IMAGE ?= mcpproxy-go
VERSION ?= $(shell git rev-parse --short HEAD)

# Build and load single-platform image locally (bake group: dev)
# Note: override the target's build arg directly. Variables in docker-bake.hcl
# are not overridden via --set; use target attributes instead.
build:
	docker buildx bake dev --set app.args.VERSION=$(VERSION)

# Build multi-arch and push (bake group: release)
release:
	docker buildx bake release --push --set app.args.VERSION=$(VERSION)

# Optional: build with explicit tags (replaces/augments defaults)
# Use two --set entries to specify multiple tags.
build-tags:
	docker buildx bake dev \
	  --set app.args.VERSION=$(VERSION) \
	  --set app.tags=$(IMAGE):$(VERSION) \
	  --set app.tags=$(IMAGE):latest

# Show resolved bake plan (debug)
print:
	docker buildx bake --print
