#!/usr/bin/env bash
# ============================================================================
# serve.sh — Kubernetes entrypoint for GLM-5.3-Flash-EXL3 on TensorFold (GB10)
# ============================================================================
# Ported from MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold.
# Runs inside the ghcr.io/miaai-lab/tensorfold-glm53 container.
#
# Env vars (set by the chart via TENSORFOLD_*):
#   TENSORFOLD_NODE_RANK         0 (leader) or 1 (worker)
#   TENSORFOLD_MASTER_ADDR       leader's fabric IP
#   TENSORFOLD_WORKER_ADDR       worker's fabric IP
#   TENSORFOLD_BEACON_PORT       worker beacon port (default 25099)
#   TENSORFOLD_MASTER_PORT       torch distributed master port (default 25000)
#   TENSORFOLD_MODEL_DIR         path to the checkpoint
#   TENSORFOLD_SERVED_MODEL_NAME model id served by the API
#   TENSORFOLD_MAX_MODEL_LEN     max context length
#   TENSORFOLD_KV_CACHE_DTYPE    KV cache dtype (default fp8)
#   TENSORFOLD_SPEC_METHOD       speculative decoding method (default dflash2)
#   TENSORFOLD_SPEC_TOKENS       draft tokens per step (default 7)
#   TENSORFOLD_PARALLEL          concurrent request streams (default 4)
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
MODEL_DIR="${TENSORFOLD_MODEL_DIR:-}"
SERVED_MODEL="${TENSORFOLD_SERVED_MODEL_NAME:-GLM-5.3-Flash-EXL3}"
MAX_MODEL_LEN="${TENSORFOLD_MAX_MODEL_LEN:-1048576}"
KV_CACHE_DTYPE="${TENSORFOLD_KV_CACHE_DTYPE:-fp8}"
SPEC_METHOD="${TENSORFOLD_SPEC_METHOD:-dflash2}"
SPEC_TOKENS="${TENSORFOLD_SPEC_TOKENS:-7}"
PARALLEL="${TENSORFOLD_PARALLEL:-4}"
API_KEYS="${TENSORFOLD_API_KEYS:-}"
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

step 1 "configuration validated (rank=${RANK}, model=${SERVED_MODEL}, max_len=${MAX_MODEL_LEN}, kv=${KV_CACHE_DTYPE}, spec=${SPEC_METHOD}/${SPEC_TOKENS}, parallel=${PARALLEL})"

# ── 2. Worker: beacon loop ──
if [[ "${RANK}" == "1" ]]; then
  step 2 "worker beacon on :${BEACON_PORT}"
  if [[ -n "${DRY_RUN}" ]] || [[ -n "${APPLY_ONLY}" ]]; then
    log "dry-run: worker beacon not started"
    exit 0
  fi
  # Simple TCP beacon: listen until the leader connects, then proceed.
  while true; do
    if echo "ready" | nc -l -p "${BEACON_PORT}" -q 1 2>/dev/null; then
      log "beacon: leader connected"
      break
    fi
    sleep 2
  done
  log "beacon done, entering serve loop"
fi

# ── 3. Leader: wait for worker beacon ──
if [[ "${RANK}" == "0" ]]; then
  step 3 "waiting for worker beacon at ${WORKER_ADDR}:${BEACON_PORT}"
  if [[ -z "${DRY_RUN}" ]]; then
    deadline=$((SECONDS + 600))
    until echo "ping" | nc -w 2 "${WORKER_ADDR}" "${BEACON_PORT}" 2>/dev/null | grep -q "ready"; do
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

# Build the launch command. TensorFold uses torchrun for TP.
LAUNCH_ARGS=(
  --nnodes=2
  --nproc-per-node=1
  --node-rank="${RANK}"
  --master-addr="${MASTER_ADDR}"
  --master-port="${MASTER_PORT}"
)

# The actual TensorFold serve command will depend on the image's entrypoint.
# This script assumes the image has a `tensorfold-serve` or equivalent command.
# For now, exec into the image's default serve path with env-configured params.
exec torchrun "${LAUNCH_ARGS[@]}" -m tensorfold.serve \
  --model "${MODEL_DIR}" \
  --served-model-name "${SERVED_MODEL}" \
  --max-model-len "${MAX_MODEL_LEN}" \
  --kv-cache-dtype "${KV_CACHE_DTYPE}" \
  --speculative-method "${SPEC_METHOD}" \
  --num-speculative-tokens "${SPEC_TOKENS}" \
  --max-num-seqs "${PARALLEL}" \
  ${EXTRA_ARGS}