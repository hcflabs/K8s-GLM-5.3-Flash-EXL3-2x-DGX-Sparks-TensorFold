#!/usr/bin/env bash
# ============================================================================
# serve.sh — Kubernetes entrypoint for GLM-5.3-Flash-EXL3 on TensorFold (GB10)
# ============================================================================
# Ported from MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold.
# Runs inside ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold.
# Upstream launches the image with the container command `tensorfold serve ...`
# (the image's ENTRYPOINT is NVIDIA's nvidia_entrypoint.sh, CMD is unset), so
# here we `exec tensorfold serve ...` directly.
#
# Env vars (set by the chart via TENSORFOLD_*):
#   TENSORFOLD_NODE_RANK         0 (leader) or 1 (worker)
#   TENSORFOLD_MASTER_ADDR       leader's fabric IP
#   TENSORFOLD_WORKER_ADDR       worker's fabric IP
#   TENSORFOLD_BEACON_PORT       worker beacon port (default 25099)
#   TENSORFOLD_MASTER_PORT       torch distributed master port (default 25000)
#   TENSORFOLD_API_PORT          HTTP serve port (default 8888)
#   TENSORFOLD_MODEL_DIR         path to the checkpoint
#   TENSORFOLD_SERVED_MODEL_NAME model id served by the API (--name)
#   TENSORFOLD_MAX_MODEL_LEN     --context (default 1048576)
#   TENSORFOLD_MAX_TOKENS        --max-tokens reply budget (default 4096)
#   TENSORFOLD_KV_CACHE_DTYPE    fp8 (TF_GLM_KV) or bf16|int8|int4 (--kv-dtype)
#   TENSORFOLD_THINKING          "1" = --thinking, else --no-thinking
#   TENSORFOLD_VISION            "1" = --vision
#   TENSORFOLD_SPEC_METHOD       none|auto, or the method name (dflash2) served by the mounted drafter
#   TENSORFOLD_DRAFTER_PATH      mounted path of the drafter checkpoint (used as --drafter)
#   TENSORFOLD_PARALLEL          --parallel concurrent streams (default 4)
#   TENSORFOLD_API_KEYS          optional API key(s)
#   TENSORFOLD_EXTRA_ARGS        extra arguments appended verbatim
#   TENSORFOLD_CHECK_ALL=1       dry-run: print every step and exit before launch
#   TENSORFOLD_APPLY_ONLY=1      stop before launching the server
set -euo pipefail

RANK="${TENSORFOLD_NODE_RANK:-}"
MASTER_ADDR="${TENSORFOLD_MASTER_ADDR:-}"
WORKER_ADDR="${TENSORFOLD_WORKER_ADDR:-}"
BEACON_PORT="${TENSORFOLD_BEACON_PORT:-25099}"
MASTER_PORT="${TENSORFOLD_MASTER_PORT:-25000}"
API_PORT="${TENSORFOLD_API_PORT:-8888}"
MODEL_DIR="${TENSORFOLD_MODEL_DIR:-}"
SERVED_MODEL="${TENSORFOLD_SERVED_MODEL_NAME:-GLM-5.3-Flash-EXL3}"
MAX_MODEL_LEN="${TENSORFOLD_MAX_MODEL_LEN:-1048576}"
MAX_TOKENS="${TENSORFOLD_MAX_TOKENS:-4096}"
KV_CACHE_DTYPE="${TENSORFOLD_KV_CACHE_DTYPE:-fp8}"
THINKING="${TENSORFOLD_THINKING:-1}"
VISION="${TENSORFOLD_VISION:-0}"
SPEC_METHOD="${TENSORFOLD_SPEC_METHOD:-dflash2}"
DRAFTER_PATH="${TENSORFOLD_DRAFTER_PATH:-}"
PARALLEL="${TENSORFOLD_PARALLEL:-4}"
API_KEYS="${TENSORFOLD_API_KEYS:-}"
export API_KEYS
EXTRA_ARGS="${TENSORFOLD_EXTRA_ARGS:-}"

DRY_RUN="${TENSORFOLD_CHECK_ALL:-}"
APPLY_ONLY="${TENSORFOLD_APPLY_ONLY:-}"

log() { echo "[tensorfold rank=${RANK}] $(date -u +%T) $*"; }
step() { log "STEP $1: $2"; }

if [[ -n "${DRY_RUN}" ]]; then
  log "check-all mode: reporting only, will not launch"
fi

# ── 1. Validate required inputs ──
[[ -n "${RANK}" ]]    || { log "FATAL: TENSORFOLD_NODE_RANK is not set"; exit 1; }
[[ -n "${MASTER_ADDR}" ]] || { log "FATAL: TENSORFOLD_MASTER_ADDR is not set"; exit 1; }
[[ -n "${MODEL_DIR}" ]]   || { log "FATAL: TENSORFOLD_MODEL_DIR is not set"; exit 1; }
[[ -d "${MODEL_DIR}" ]]   || { log "FATAL: model dir ${MODEL_DIR} does not exist"; exit 1; }
[[ -f "${MODEL_DIR}/config.json" ]] || { log "FATAL: config.json missing from ${MODEL_DIR}"; exit 1; }
[[ -n "$SPEC_METHOD" ]] || { log "FATAL: TENSORFOLD_SPEC_METHOD is not a drafter repo, none, or auto"; exit 1; }

step 1 "configuration validated (rank=${RANK}, model=${SERVED_MODEL}, context=${MAX_MODEL_LEN}, max_tokens=${MAX_TOKENS}, kv=${KV_CACHE_DTYPE}, drafter=${SPEC_METHOD}, parallel=${PARALLEL})"

# ── 2. Worker: beacon loop ──
if [[ "${RANK}" == "1" ]]; then
  step 2 "worker beacon on :${BEACON_PORT}"
  if [[ -n "${DRY_RUN}" ]] || [[ -n "${APPLY_ONLY}" ]]; then
    log "dry-run: worker beacon not started"
    exit 0
  fi
  # Simple TCP beacon: answer "ready" until the leader's serve.sh probe (step 3)
  # has connected. The wait-for-worker init container connects first, so the
  # beacon keeps answering; it exits once a second connection arrives, or after
  # 30s with no connection once the first one has been served.
  # python3, not nc: the serving image ships no netcat, and a missing nc used to
  # fail silently here (stderr discarded) and spin forever.
  python3 -c 'import socket,sys
srv = socket.create_server(("", int(sys.argv[1])))
served = 0
while served < 2:
    srv.settimeout(30 if served else None)
    try:
        c, _ = srv.accept()
    except socket.timeout:
        break
    with c:
        c.sendall(b"ready\n")
    served += 1' "${BEACON_PORT}" || { log "FATAL: beacon could not listen on :${BEACON_PORT}"; exit 1; }
  log "beacon: leader connected"
  log "beacon done, entering serve loop"
fi

# ── 3. Leader: wait for worker beacon ──
if [[ "${RANK}" == "0" ]]; then
  step 3 "waiting for worker beacon at ${WORKER_ADDR}:${BEACON_PORT}"
  if [[ -z "${DRY_RUN}" ]]; then
    deadline=$((SECONDS + 600))
    until python3 -c 'import socket,sys
try:
    s = socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=2)
    s.sendall(b"ping\n")
    sys.exit(0 if b"ready" in s.recv(64) else 1)
except OSError:
    sys.exit(1)' "${WORKER_ADDR}" "${BEACON_PORT}"; do
      if ((SECONDS > deadline)); then
        log "FATAL: worker beacon at ${WORKER_ADDR}:${BEACON_PORT} did not answer in 10m"
        exit 1
      fi
      sleep 3
    done
    log "worker beacon answered"
  fi
fi

# ── 4. Launch TensorFold ──
step 4 "launching TensorFold"

if [[ -n "${DRY_RUN}" ]] || [[ -n "${APPLY_ONLY}" ]]; then
  log "dry-run: TensorFold not launched"
  log "all steps processed"
  exit 0
fi

# A mounted drafter path wins; otherwise none|auto pass through, and any other
# value is treated as a repo/path.
if [[ -n "$DRAFTER_PATH" ]]; then
  DRAFTER_ARG="$DRAFTER_PATH"
elif [[ "$SPEC_METHOD" == "none" || "$SPEC_METHOD" == "auto" || -z "$SPEC_METHOD" ]]; then
  DRAFTER_ARG="$SPEC_METHOD"
else
  DRAFTER_ARG="$SPEC_METHOD"
fi

# Build the `tensorfold serve` command (one process per rank, TP=2). The flags
# mirror the upstream start.sh launch: --tp/--rank/--master(-port) for the
# two-rank CUDA engine, --name/--host/--port for the OpenAI-compatible server,
# --context/--max-tokens/--parallel/--drafter for generation.
LAUNCH_ARGS=(
  serve "$MODEL_DIR"
  --tp 2
  --rank "$RANK"
  --master "$MASTER_ADDR"
  --master-port "$MASTER_PORT"
  --name "$SERVED_MODEL"
  --host 0.0.0.0
  --port "$API_PORT"
  --context "$MAX_MODEL_LEN"
  --max-tokens "$MAX_TOKENS"
  --parallel "$PARALLEL"
  --drafter "$DRAFTER_ARG"
)

# KV cache: the exact fp8 cache is a TensorFold GLM switch (TF_GLM_KV), not a
# --kv-dtype value; bf16/int8/int4 go through --kv-dtype.
if [[ "$KV_CACHE_DTYPE" == "fp8" ]]; then
  export TF_GLM_KV=fp8
else
  LAUNCH_ARGS+=(--kv-dtype "$KV_CACHE_DTYPE")
fi

# Thinking and vision are boolean serve flags.
if [[ "$THINKING" == "1" ]]; then LAUNCH_ARGS+=(--thinking); else LAUNCH_ARGS+=(--no-thinking); fi
[[ "$VISION" == "1" ]] && LAUNCH_ARGS+=(--vision)

# shellcheck disable=SC2206
EXTRA=($EXTRA_ARGS)

log "exec: tensorfold ${LAUNCH_ARGS[*]} ${EXTRA[*]}"
exec tensorfold "${LAUNCH_ARGS[@]}" "${EXTRA[@]}"
