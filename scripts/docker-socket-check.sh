#!/usr/bin/env sh
set -eu

echo "[docker-socket-check] id: $(id || true)"
echo "[docker-socket-check] DOCKER_HOST: ${DOCKER_HOST:-}"
echo "[docker-socket-check] socket perms:"
ls -l /var/run/docker.sock || true

echo "[docker-socket-check] docker version:" 
if docker version >/dev/null 2>&1; then
  echo "OK: Docker reachable from container"
  exit 0
else
  rc=$?
  echo "FAIL: docker not reachable (exit $rc)"
  docker -v || true
  exit $rc
fi

