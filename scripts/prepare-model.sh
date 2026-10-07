#!/usr/bin/env bash
# Host-side checkpoint download. Run from your workstation; SSHes to each Spark
# and downloads the FULL checkpoint on both (tensor parallelism shards tensors
# at load time, so neither node can hold half). ~176 GiB per node for the model,
# ~1-2 GiB for the DFlash2 drafter.
#
# Usage: scripts/prepare-model.sh [options] user@host [user@host ...]
#
# Options:
#   --models-dir DIR     weights root on each node (REQUIRED, e.g. /data/models)
#   --repo ID            model repo id (default: the published checkpoint, or the
#                        Ablit repo with --ablit)
#   --revision SHA       override the pinned model revision
#   --ablit              download the gated Ablit weights (requires HF_TOKEN)
#   --drafter            also download the DFlash2 drafter (incoai/GLM-5.3-Flash-DFlash2)
#   --drafter-repo ID    drafter repo id (default: incoai/GLM-5.3-Flash-DFlash2)
#   --dry-run            print what would run on each host and stop
#   -h, --help
#
# Env: HF_TOKEN (required with --ablit; sent to the host over stdin, never on a
# command line).
#
# Resumable: re-running continues a partial download. The chart's
# weights.hostPath.* must point at <models-dir>/<dir name printed below>, and
# with a drafter, weights.drafter.hostPath.* at <models-dir>/<drafter dir>.
set -euo pipefail

MODELS_DIR=""
REVISION=""
REPO=""
DRAFTER=0
DRAFTER_REPO=""
DRY=0
ABLIT=0
HOSTS=()

DEFAULT_REPO="Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold"
ABLIT_REPO="Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold-Ablit"
# Pinned revisions (from the upstream recipe config.sh); empty follows the tip.
PIN_REPO="078455ffe6472f9a52fbc1139f58b9db2881b25c"
PIN_ABLIT="57edefd2f5d9b371c8345883304d5af68b52fa24"
PIN_DRAFTER="bf582e4eacc1810f76656d1811693ff6c6737d2a"
DEFAULT_DRAFTER_REPO="incoai/GLM-5.3-Flash-DFlash2"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --models-dir) MODELS_DIR="${2:?}"; shift 2 ;;
    --revision) REVISION="${2-}"; shift 2 ;;
    --repo) REPO="${2:?}"; shift 2 ;;
    --ablit) ABLIT=1; shift ;;
    --drafter) DRAFTER=1; shift ;;
    --drafter-repo) DRAFTER_REPO="${2:?}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) HOSTS+=("$1"); shift ;;
  esac
done

[[ -n "${MODELS_DIR}" ]] || { echo "error: --models-dir is required" >&2; usage >&2; exit 2; }
[[ ${#HOSTS[@]} -ge 1 ]] || { echo "error: give at least one user@host (normally both Sparks)" >&2; usage >&2; exit 2; }

# Resolve the model repo/revision. --ablit switches to the gated Ablit weights.
if [[ "${ABLIT}" -eq 1 ]]; then
  [[ -n "${HF_TOKEN:-}" ]] || { echo "error: --ablit downloads gated weights; set HF_TOKEN" >&2; exit 2; }
  REPO="${REPO:-${ABLIT_REPO}}"
  : "${REVISION:=${PIN_ABLIT}}"
else
  REPO="${REPO:-${DEFAULT_REPO}}"
  : "${REVISION:=${PIN_REPO}}"
fi

MODEL_DEST="${MODELS_DIR}/$(basename "${REPO}")"
if [[ "${DRAFTER}" -eq 1 ]]; then
  DRAFTER_REPO="${DRAFTER_REPO:-${DEFAULT_DRAFTER_REPO}}"
  DRAFTER_DEST="${MODELS_DIR}/$(basename "${DRAFTER_REPO}")"
  DRAFTER_ARGS=( "${DRAFTER_REPO}" "${PIN_DRAFTER}" "${DRAFTER_DEST}" )
else
  DRAFTER_DEST=""
  DRAFTER_ARGS=()
fi

echo "model:    ${REPO}${REVISION:+ @${REVISION}}"
echo "  -> ${MODEL_DEST}   (chart: weights.hostPath.*, model.dirName=${MODEL_DEST##*/})"
if [[ "${DRAFTER}" -eq 1 ]]; then
  echo "drafter:  ${DRAFTER_REPO} @${PIN_DRAFTER}"
  echo "  -> ${DRAFTER_DEST}   (chart: weights.drafter.hostPath.*, model.drafter.dirName=${DRAFTER_DEST##*/})"
else
  echo "drafter:  not downloaded (use --drafter, or set serving.speculative.method: none to serve without one)"
fi

# One remote script per host downloads every artifact in a single SSH session.
remote_script() {
  local mrepo="$1" mrev="$2" mdest="$3"
  local drepo="${4:-}" drev="${5:-}" ddest="${6:-}"
  if [[ -n "$drepo" ]]; then
    drafter_dl="dl '${drepo}' '${drev}' '${ddest}' 0"
  else
    drafter_dl=""
  fi
  cat <<REMOTE
set -euo pipefail
export HF_HUB_ENABLE_HF_TRANSFER=0
[ -n "\${HF_TOKEN:-}" ] || unset HF_TOKEN
if [ ! -x "\$HOME/.cache/glm-flash-exl3-tensorfold-venv/bin/python" ]; then
  mkdir -p "\$HOME/.cache"
  python3 -m venv "\$HOME/.cache/glm-flash-exl3-tensorfold-venv"
fi
"\$HOME/.cache/glm-flash-exl3-tensorfold-venv/bin/pip" -q install -U huggingface_hub
HF="\$HOME/.cache/glm-flash-exl3-tensorfold-venv/bin/hf"
dl() {
  local repo=\$1 rev=\$2 dest=\$3 need_config=\$4
  sudo mkdir -p "\$dest" '${MODELS_DIR}'
  sudo chown -R "\$(id -u):\$(id -g)" "\$dest"
  if [ -n "\$rev" ]; then REVARG="--revision \$rev"; else REVARG=""; fi
  echo "[\$(hostname)] downloading \$repo -> \$dest"
  \$HF download "\$repo" \$REVARG --local-dir "\$dest" --max-workers 16
  if [ "\$need_config" = 1 ]; then
    test -f "\$dest/config.json" || { echo "[\$(hostname)] config.json missing after download of \$repo" >&2; exit 1; }
  fi
}
dl '${mrepo}' '${mrev}' '${mdest}' 1
${drafter_dl}
echo "[\$(hostname)] done"
REMOTE
}

if [[ "${DRY}" -eq 1 ]]; then
  for h in "${HOSTS[@]}"; do
    echo "--- would run on ${h} ---"
    remote_script "${REPO}" "${REVISION}" "${MODEL_DEST}" "${DRAFTER_ARGS[@]}"
  done
  exit 0
fi

pids=()
for h in "${HOSTS[@]}"; do
  { printf '%s\n' "${HF_TOKEN:-}"; remote_script "${REPO}" "${REVISION}" "${MODEL_DEST}" "${DRAFTER_ARGS[@]}"; } |
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${h}" 'IFS= read -r HF_TOKEN; export HF_TOKEN; bash -s' 2>&1 |
    sed "s|^|${h}: |" &
  pids+=($!)
done

rc=0
for p in "${pids[@]}"; do wait "${p}" || rc=1; done
[[ "${rc}" -eq 0 ]] && echo "all hosts complete" || echo "one or more hosts failed (re-run to resume)" >&2
exit "${rc}"
