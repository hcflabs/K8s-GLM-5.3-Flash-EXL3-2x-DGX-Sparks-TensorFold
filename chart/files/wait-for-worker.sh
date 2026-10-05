#!/usr/bin/env bash
# ── wait-for-worker.sh: init container that blocks until the worker beacon answers ──
set -euo pipefail

WORKER_ADDR="${TENSORFOLD_WORKER_ADDR:?TENSORFOLD_WORKER_ADDR must be set}"
BEACON_PORT="${TENSORFOLD_BEACON_PORT:-25099}"
DEADLINE="${TENSORFOLD_BEACON_DEADLINE:-600}"

deadline=$((SECONDS + DEADLINE))
until echo "ping" | nc -w 2 "${WORKER_ADDR}" "${BEACON_PORT}" 2>/dev/null | grep -q "ready"; do
  if ((SECONDS > deadline)); then
    echo "FATAL: worker beacon at ${WORKER_ADDR}:${BEACON_PORT} did not answer in ${DEADLINE}s" >&2
    exit 1
  fi
  sleep 3
done
echo "worker beacon answered"