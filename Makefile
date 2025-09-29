.PHONY: build build-slim build-full release print \
	run-slim run-full run-full-check run-both down logs ps restart .dirs \
	context-snapshot context-list context-probe

# Override as needed: IMAGE=ghcr.io/you/mcpproxy VERSION=vX.Y.Z
IMAGE  ?= ghcr.io/smart-mcp-proxy/mcpproxy
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || git rev-parse --short HEAD)
GIT_SHA ?= $(shell git rev-parse HEAD)

# Pick docker compose command (plugin or standalone) robustly
# Prefer plugin if `docker compose version` output contains "Docker Compose version"
DC := $(shell if docker compose version 2>/dev/null | grep -q "Docker Compose version"; then \
               echo "docker compose"; \
             elif command -v docker-compose >/dev/null 2>&1; then \
               echo "docker-compose"; \
             else \
               echo ""; \
             fi)

ifeq ($(strip $(DC)),)
$(error Docker Compose not found. Install the Compose plugin (docker compose) or docker-compose. On macOS update Docker Desktop; on Debian/Ubuntu: sudo apt-get install docker-compose-plugin)
endif

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

# -----------------------------------------------------------------------------
# Runtime helpers via docker compose
# -----------------------------------------------------------------------------

DIRS := config data logs
.dirs:
	@mkdir -p $(DIRS)

# Run slim variant (distroless). Builds image first, then starts with profile.
run-slim: build-slim .dirs
	IMAGE=$(IMAGE) VERSION=$(VERSION) $(DC) up -d slim

# Run full variant (Debian with runtimes). Builds image first, then starts.
run-full: build-full .dirs
	@set -e; \
	# Detect the GID that owns /var/run/docker.sock inside the engine (works on Linux/macOS/Windows)
	if [ -z "$$DOCKER_GID" ]; then \
	  GID=$$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock busybox:1.36 sh -lc 'stat -c %g /var/run/docker.sock 2>/dev/null || ls -ln /var/run/docker.sock | awk "{print \$4}"' || true); \
	  if [ -n "$$GID" ]; then \
	    echo "Using DOCKER_GID=$$GID (from daemon socket owner)"; \
	    export DOCKER_GID=$$GID; \
	  else \
	    echo "Warning: could not detect GID of /var/run/docker.sock; socket access may fail. Set DOCKER_GID manually if needed."; \
	  fi; \
	fi; \
	IMAGE=$(IMAGE) VERSION=$(VERSION) $(DC) up -d full

# Build, run, then verify Docker access from inside the container
run-full-check: run-full
	@echo "Verifying Docker access inside 'full' service..."; \
	set -e; \
	for i in $$(seq 1 10); do \
	  if $(DC) exec -T full sh -lc 'command -v docker-socket-check >/dev/null 2>&1 && docker-socket-check || docker version >/dev/null 2>&1'; then \
	    echo "Docker access OK inside container."; \
	    exit 0; \
	  fi; \
	  echo "Waiting for container/docker... ($$i/10)"; \
	  sleep 1; \
	done; \
	echo "ERROR: Docker CLI inside container cannot reach host daemon."; \
	echo "--- debug: inside container ---"; \
	$(DC) exec -T full sh -lc 'id; ls -l /var/run/docker.sock || true; getent group 2>/dev/null | grep docker || true'; \
	echo "------------------------------"; \
	echo "Hint: try setting DOCKER_GID to the socket GID shown above."; \
	exit 1

# Run both variants concurrently (distinct host ports)
run-both: build .dirs
	IMAGE=$(IMAGE) VERSION=$(VERSION) $(DC) up -d

# Stop and remove containers, networks, etc. from this compose file
down:
	$(DC) down

# Tail logs from the running container
logs:
	$(DC) logs -f --tail=200

# Show running services/containers for this compose project
ps:
	$(DC) ps

# Restart currently running compose services
restart:
	$(DC) restart

# -----------------------------------------------------------------------------
# Docker context helpers (verify .dockerignore behavior)
# -----------------------------------------------------------------------------

# Snapshot the Docker build context (after .dockerignore) to a local folder.
# Inspect: .docker-context-snapshot/snapshot
context-snapshot:
	@rm -rf .docker-context-snapshot
	@echo "Building context snapshot to .docker-context-snapshot/..."
	@printf 'FROM scratch\nCOPY . /snapshot\n' | docker buildx build -f - --output type=local,dest=.docker-context-snapshot .
	@echo "Done. See .docker-context-snapshot/snapshot"

# List files included in the build context (uses the snapshot above).
context-list: context-snapshot
	@echo "Files in Docker context (top 3 levels):"
	@cd .docker-context-snapshot/snapshot && find . -maxdepth 3 -print | sort

# Probe for a specific file path in the context snapshot.
# Usage: make context-probe FILE=path/to/file
FILE ?=
context-probe: context-snapshot
	@if [ -z "$(FILE)" ]; then \
	  echo "Usage: make context-probe FILE=path/to/file"; \
	  exit 2; \
	fi
	@if [ -e ".docker-context-snapshot/snapshot/$(FILE)" ]; then \
	  echo "FOUND: $(FILE)"; \
	else \
	  echo "MISSING: $(FILE)"; \
	  exit 1; \
	fi
