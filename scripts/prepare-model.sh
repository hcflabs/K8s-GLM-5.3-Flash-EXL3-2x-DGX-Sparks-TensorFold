#!/usr/bin/env bash
# Host-side checkpoint download. Run from your workstation; SSHes to each Spark
# and downloads the FULL checkpoint on both (tensor parallelism shards tensors
# at load time, so neither node can hold half). ~176 GiB per node.
#
# Usage: scripts/prepare-model.sh [options] user@host [user@host ...]
#
# Options:
#   --models-dir DIR   weights root on each node (REQUIRED, e.g. /data/models)
#   --revision SHA     override the pinned revision (pass "" to follow the tip of main)
#   --repo ID          repository id (default: Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold)
#   --dry-run          print what would run on each host and stop
#   -h, --help
#
# Env: HF_TOKEN (optional; sent to the host over stdin, never on a command line).
#
# Resumable: re-running continues a partial download. The chart's
# weights.hostPath.* must point at <models-dir>/<dir name printed below>.
set -euo pipefail

MODELS_DIR=""
REVISION=""
REPO=""
DRY=0
HOSTS=()

DEFAULT_REPO="Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold"
DEFAULT_REVISION=""

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --models-dir) MODELS_DIR="${2:?}"; shift 2 ;;
    --revision) REVISION="${2-}"; shift 2 ;;
    --repo) REPO="${2:?}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) HOSTS+=("$1"); shift ;;
  esac
done

[[ -n "${MODELS_DIR}" ]] || { echo "error: --models-dir is required" >&2; usage >&2; exit 2; }
[[ ${#HOSTS[@]} -ge 1 ]] || { echo "error: give at least one user@host (normally both Sparks)" >&2; usage >&2; exit 2; }

REPO="${REPO:-${DEFAULT_REPO}}"

DIR_NAME="$(basename "${REPO}")"
DEST="${MODELS_DIR}/${DIR_NAME}"

remote_script() {
  cat <<REMOTE
set -euo pipefail
export HF_HUB_ENABLE_HF_TRANSFER=0
[ -n "\${HF_TOKEN:-}" ] || unset HF_TOKEN
sudo mkdir -p '${DEST}' '${MODELS_DIR}'
sudo chown -R "\$(id -u):\$(id -g)" '${DEST}'
if [ ! -x "\$HOME/.cache/glm-tensorfold-venv/bin/python" ]; then
  mkdir -p "\$HOME/.cache"
  python3 -m venv "\$HOME/.cache/glm-tensorfold-venv"
fi
"\$HOME/.cache/glm-tensorfold-venv/bin/pip" -q install -U huggingface_hub
HF="\$HOME/.cache/glm-tensorfold-venv/bin/hf"
if [ -n '${REVISION}' ]; then REVARG="--revision ${REVISION}"; else REVARG=""; fi
echo "[\$(hostname)] downloading ${REPO} -> ${DEST}"
\$HF download '${REPO}' \$REVARG --local-dir '${DEST}' --max-workers 16
test -f '${DEST}/config.json' || { echo "[\$(hostname)] config.json missing after download" >&2; exit 1; }
REMOTE
  echo 'echo "[$(hostname)] done"'
}

echo "repo=${REPO} revision=${REVISION:-<tip of main>}"
echo "weights dir on each node: ${DEST}   (chart: weights.hostPath.* and model.dirName=${DIR_NAME})"

if [[ "${DRY}" -eq 1 ]]; then
  for h in "${HOSTS[@]}"; do
    echo "--- would run on ${h} ---"
    remote_script
  done
  exit 0
fi

pids=()
for h in "${HOSTS[@]}"; do
  { printf '%s\n' "${HF_TOKEN:-}"; remote_script; } |
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${h}" 'IFS= read -r HF_TOKEN; export HF_TOKEN; bash -s' 2>&1 |
    sed "s|^|${h}: |" &
  pids+=($!)
done

rc=0
for p in "${pids[@]}"; do wait "${p}" || rc=1; done
[[ "${rc}" -eq 0 ]] && echo "all hosts complete" || echo "one or more hosts failed (re-run to resume)" >&2
exit "${rc}"