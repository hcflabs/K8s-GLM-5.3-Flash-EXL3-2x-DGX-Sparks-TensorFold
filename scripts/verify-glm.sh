#!/usr/bin/env bash
# One-shot readiness report for the two-node deployment: weights, image, fabric,
# rank labels, pods, and the served model. Read-only. Reports every prerequisite
# and points at the first one that is not ready.
#
# The Sparks are reached over SSH because their kubelets are usually unreachable
# from the API server (:10250), so `kubectl logs/exec` may not work either.
#
# Usage: scripts/verify-glm.sh --leader user@host --worker user@host [options]
#   --leader / --worker USER@HOST  SSH targets (or env LEADER_SSH / WORKER_SSH)
#   --leader-fabric-ip IP          REQUIRED (chart topology.fabric.masterAddr)
#   --worker-fabric-ip IP          REQUIRED (chart topology.fabric.workerAddr)
#   --fabric-if NAME               REQUIRED (chart topology.fabric.interface)
#   --rdma-dev NAME                REQUIRED (chart topology.fabric.rdmaDevice)
#   --model-dir PATH               REQUIRED: weights dir on each node (chart weights.hostPath.*)
#   --min-gib N                    weights are "complete" at >= N GiB (default 160)
#   --model NAME                   served model name (default GLM-5.3-Flash-EXL3)
#   --max-model-len N              default 1048576
#   --image-ref TEXT               substring identifying the image in `crictl images` (optional)
#   --rank-label-key KEY           default node.tensorfold/rank
#   -n NAMESPACE                   default tensorfold
#   --api-url URL                  default http://<leader host>:8888
#   --watch [SECONDS]              refresh until Ctrl-C (default 30)
#   --bench                        also run ib_write_bw across the fabric
# Env: the REQUIRED values above may also be set as env vars; API_KEY (bearer token for /v1 when auth is enabled)
set -euo pipefail

LEADER_SSH="${LEADER_SSH:-}"
WORKER_SSH="${WORKER_SSH:-}"
LEADER_FABRIC_IP="${LEADER_FABRIC_IP:-}"
WORKER_FABRIC_IP="${WORKER_FABRIC_IP:-}"
FABRIC_IF="${FABRIC_IF:-}"
RDMA_DEV="${RDMA_DEV:-}"
MODEL_DIR="${MODEL_DIR:-}"
MIN_GIB=160
SERVED_MODEL="${SERVED_MODEL:-GLM-5.3-Flash-EXL3}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-1048576}"
IMAGE_REF="${IMAGE_REF:-glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold}"
RANK_KEY="${RANK_KEY:-node.tensorfold/rank}"
NAMESPACE="${NAMESPACE:-tensorfold}"
API_URL="${API_URL:-}"
WATCH="${WATCH:-0}"
WATCH_INTERVAL="${WATCH_INTERVAL:-30}"
BENCH="${BENCH:-0}"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --leader) LEADER_SSH="${2:?}"; shift 2 ;;
    --worker) WORKER_SSH="${2:?}"; shift 2 ;;
    --leader-fabric-ip) LEADER_FABRIC_IP="${2:?}"; shift 2 ;;
    --worker-fabric-ip) WORKER_FABRIC_IP="${2:?}"; shift 2 ;;
    --fabric-if) FABRIC_IF="${2:?}"; shift 2 ;;
    --rdma-dev) RDMA_DEV="${2:?}"; shift 2 ;;
    --model-dir) MODEL_DIR="${2:?}"; shift 2 ;;
    --min-gib) MIN_GIB="${2:?}"; shift 2 ;;
    --model) SERVED_MODEL="${2:?}"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="${2:?}"; shift 2 ;;
    --image-ref) IMAGE_REF="${2:?}"; shift 2 ;;
    --rank-label-key) RANK_KEY="${2:?}"; shift 2 ;;
    -n) NAMESPACE="${2:?}"; shift 2 ;;
    --api-url) API_URL="${2:?}"; shift 2 ;;
    --watch) WATCH=1; if [[ "${2:-}" =~ ^[0-9]+$ ]]; then WATCH_INTERVAL="$2"; shift; fi; shift ;;
    --bench) BENCH=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "${LEADER_SSH}" && -n "${WORKER_SSH}" && -n "${LEADER_FABRIC_IP}" && -n "${WORKER_FABRIC_IP}" &&
  -n "${FABRIC_IF}" && -n "${RDMA_DEV}" && -n "${MODEL_DIR}" ]] || {
  echo "error: --leader --worker --leader-fabric-ip --worker-fabric-ip --fabric-if --rdma-dev --model-dir are required" >&2
  usage >&2
  exit 2
}
LEADER_HOST="${LEADER_SSH##*@}"
API_URL="${API_URL:-http://${LEADER_HOST}:8888}"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m' RESET=$'\033[0m'
else
  BOLD='' DIM='' GREEN='' YELLOW='' RED='' RESET=''
fi

FIRST_PROBLEM=""
ok() { printf '%s\n' "  ${GREEN}ok${RESET}      $*"; }
warn() { printf '%s\n' "  ${YELLOW}pending${RESET} $*"; [[ -n "${FIRST_PROBLEM}" ]] || FIRST_PROBLEM="$*"; }
bad() { printf '%s\n' "  ${RED}problem${RESET} $*"; [[ -n "${FIRST_PROBLEM}" ]] || FIRST_PROBLEM="$*"; }
note() { printf '%s\n' "  ${DIM}$*${RESET}"; }
heading() { printf '\n%s\n' "${BOLD}$*${RESET}"; }

# -n: never read stdin. Callers loop with `while read ... < <(nodes)`, and an
# ssh that reads stdin swallows the remaining node lines (only leader checked).
on_node() { ssh -n -o ConnectTimeout=5 -o BatchMode=yes "$1" "$2" 2>/dev/null; }
nodes() { printf '%s\n' "leader:${LEADER_SSH}:${WORKER_FABRIC_IP}:${LEADER_FABRIC_IP}" "worker:${WORKER_SSH}:${LEADER_FABRIC_IP}:${WORKER_FABRIC_IP}"; }

run_checks() {
  heading "Weights (${MODEL_DIR})"
  local name ssh_t peer _ out gib files
  while IFS=: read -r name ssh_t peer _; do
    out="$(on_node "${ssh_t}" "
      if [ -f ${MODEL_DIR}/config.json ]; then
        du -sb ${MODEL_DIR} | cut -f1
        find ${MODEL_DIR} -name '*.safetensors' | wc -l
      else echo missing; fi")" || { bad "${name}: unreachable over SSH"; continue; }
    if [[ -z "${out}" || "${out}" == "missing" ]]; then
      bad "${name}: no config.json in ${MODEL_DIR} (run scripts/prepare-model.sh)"
      continue
    fi
    gib="$(awk -v b="$(sed -n 1p <<<"${out}")" 'BEGIN { printf "%.1f", b / 1073741824 }')"
    files="$(sed -n 2p <<<"${out}")"
    if awk -v g="${gib}" -v m="${MIN_GIB}" 'BEGIN { exit !(g >= m) }'; then
      ok "${name}: ${gib} GiB, ${files} safetensors"
    else
      bad "${name}: only ${gib} GiB (< ${MIN_GIB}); download incomplete? re-run prepare-model.sh"
    fi
  done < <(nodes)

  heading "Container image (${IMAGE_REF})"
  local name ssh_t found
  while IFS=: read -r name ssh_t _p _m; do
    found="$(on_node "${ssh_t}" "sudo k3s crictl images --digests 2>/dev/null | grep -c '${IMAGE_REF}' || true")" || found=0
    if [[ "${found:-0}" -gt 0 ]]; then
      ok "${name}: present in containerd"
    else
      warn "${name}: not pulled yet (kubelet pulls ~10 GB on first start)"
    fi
  done < <(nodes)

  heading "Fabric (${FABRIC_IF} / ${RDMA_DEV})"
  local name ssh_t peer _ out addr state ping_rc
  while IFS=: read -r name ssh_t peer _; do
    out="$(on_node "${ssh_t}" "
      ip -4 -brief address show ${FABRIC_IF} 2>/dev/null | awk '{print \$3}'
      cat /sys/class/infiniband/${RDMA_DEV}/ports/1/state 2>/dev/null | awk '{print \$NF}'
      ping -c 1 -W 2 -I ${FABRIC_IF} ${peer} >/dev/null 2>&1 && echo up || echo down")" ||
      { bad "${name}: unreachable over SSH"; continue; }
    addr="$(sed -n 1p <<<"${out}")"
    state="$(sed -n 2p <<<"${out}")"
    ping_rc="$(sed -n 3p <<<"${out}")"
    if [[ -n "${addr}" && "${addr}" != "down" ]]; then
      ok "${name}: ${addr} on ${FABRIC_IF}"
    else
      bad "${name}: no address on ${FABRIC_IF}"
    fi
    if [[ "${state}" == "ACTIVE" ]]; then
      ok "${name}: RDMA ${RDMA_DEV} is ${state}"
    else
      bad "${name}: RDMA ${RDMA_DEV} is ${state:-missing} (NCCL will fall back to TCP)"
    fi
    if [[ "${ping_rc}" == "up" ]]; then
      ok "${name}: can reach ${peer} over ${FABRIC_IF}"
    else
      bad "${name}: cannot ping ${peer} over ${FABRIC_IF}"
    fi
  done < <(nodes)

  heading "Kubernetes"
  if ! kubectl get nodes -l "${RANK_KEY}" -o name 2>/dev/null | grep -q .; then
    warn "no nodes labeled with ${RANK_KEY}"
  else
    for n in $(kubectl get nodes -l "${RANK_KEY}" -o name 2>/dev/null); do
      node_name="${n#node/}"
      # jsonpath needs the dots in a label key escaped (node.tensorfold/rank).
      rank="$(kubectl get "${n}" -o jsonpath="{.metadata.labels.${RANK_KEY//./\\.}}" 2>/dev/null)"
      if [[ -n "${rank}" ]]; then
        ok "${node_name}: rank=${rank}"
      else
        bad "${node_name}: ${RANK_KEY}=${rank:-<empty>}"
      fi
    done
  fi

  heading "Pods"
  local pods
  pods="$(kubectl -n "${NAMESPACE}" get pods -o wide 2>/dev/null)" || true
  if [[ -z "${pods}" ]]; then
    warn "no pods in namespace ${NAMESPACE}"
  else
    echo "${pods}"
  fi

  heading "API (${API_URL}/v1/models)"
  auth=()
  [[ -z "${API_KEY:-}" ]] || auth=(-H "Authorization: Bearer ${API_KEY}")
  body="$(curl -fsS --max-time 10 ${auth[@]+"${auth[@]}"} "${API_URL}/v1/models" 2>/dev/null)" || true
  if [[ -z "${body}" ]]; then
    warn "API not reachable at ${API_URL}"
  elif echo "${body}" | python3 -c "
import json, sys
m, n = sys.argv[1], int(sys.argv[2])
sys.exit(0 if any(d.get('id') == m and d.get('max_model_len') == n for d in json.load(sys.stdin)['data']) else 1)
" "${SERVED_MODEL}" "${MAX_MODEL_LEN}"; then
    ok "${SERVED_MODEL} served with max_model_len=${MAX_MODEL_LEN}"
  else
    bad "API responded but model mismatch: ${body:0:200}"
  fi

  if [[ -n "${FIRST_PROBLEM}" ]]; then
    echo
    echo "${BOLD}First problem:${RESET} ${FIRST_PROBLEM}"
    return 1
  fi
  return 0
}

if [[ "${WATCH}" -eq 1 ]]; then
  while true; do
    clear 2>/dev/null || true
    echo "=== verify-glm.sh @ $(date) === (${WATCH_INTERVAL}s refresh, Ctrl-C to stop)"
    run_checks || true
    sleep "${WATCH_INTERVAL}"
  done
else
  run_checks
fi