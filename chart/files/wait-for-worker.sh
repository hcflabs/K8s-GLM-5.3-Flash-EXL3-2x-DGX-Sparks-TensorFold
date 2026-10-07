#!/usr/bin/env bash
# ── wait-for-worker.sh: init container that blocks until the worker beacon answers ──
set -euo pipefail

WORKER_ADDR="${TENSORFOLD_WORKER_ADDR:?TENSORFOLD_WORKER_ADDR must be set}"
BEACON_PORT="${TENSORFOLD_BEACON_PORT:-25099}"
DEADLINE="${TENSORFOLD_BEACON_DEADLINE:-600}"

deadline=$((SECONDS + DEADLINE))
# python3, not nc: the serving image ships no netcat.
until python3 -c 'import socket,sys
try:
    s = socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=2)
    s.sendall(b"ping\n")
    sys.exit(0 if b"ready" in s.recv(64) else 1)
except OSError:
    sys.exit(1)' "${WORKER_ADDR}" "${BEACON_PORT}"; do
  if ((SECONDS > deadline)); then
    echo "FATAL: worker beacon at ${WORKER_ADDR}:${BEACON_PORT} did not answer in ${DEADLINE}s" >&2
    exit 1
  fi
  sleep 3
done
echo "worker beacon answered"