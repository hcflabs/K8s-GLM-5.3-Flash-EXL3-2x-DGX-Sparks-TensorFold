# Upstream knobs -> chart values

Upstream configures the TensorFold recipe through environment variables in
`start.sh` / `scripts/config.sh`. Each knob below maps to exactly one chart
value.

## Serving and topology

| Upstream knob / flag | Chart value | Default |
| --- | --- | --- |
| `MODEL_ID` | `model.repo` (download: `scripts/prepare-model.sh`) | published checkpoint, or `model.ablitRepo` when `model.ablit: true` |
| `ABLIT` | `model.ablit` (gated; needs `HF_TOKEN` to download) | `false` |
| `SERVED_MODEL_NAME` | `model.servedName` | `GLM-5.3-Flash-EXL3` |
| checkpoint dir | `weights.hostPath.leader` / `.worker` | **required** |
| `DFLASH2_ID` | `model.drafter.repo` + `weights.drafter.hostPath.*` | `incoai/GLM-5.3-Flash-DFlash2` |
| `WORKER_WEIGHTS=nfs` | `weights.nfs.{enabled,server,path}` | off |
| `HEAD_IP` (leader fabric) | `topology.fabric.masterAddr` | **required** |
| `WORKER_IP` (worker fabric) | `topology.fabric.workerAddr` | **required** |
| `CX7_IF` | `topology.fabric.interface` | **required** |
| `CX7_RDMA` | `topology.fabric.rdmaDevice` (comma-separated for both rails of a port) | **required** |
| NCCL GID index | `topology.fabric.gidIndex` | empty (NCCL picks; RoCE gathers use 3) |
| `NCCL_CHANNELS` | `topology.fabric.ncclChannels` | `4` |
| torch distributed port | `topology.fabric.port` | `25000` |
| rank node selection | `topology.rankLabels.*` | `node.tensorfold/rank=leader\|worker` |
| `CONTEXT` | `serving.maxModelLen` | `1048576` |
| `MAX_TOKENS` | `serving.maxTokens` | `32768` |
| `KV` (fp8 / bf16 / int8 / int4) | `serving.kvCacheDtype` | `fp8` |
| `THINKING` | `serving.thinking` | `true` (or `false` with `model.ablit: true`) |
| `VISION` | `serving.vision` | `false` |
| drafter | `serving.speculative.method` (`none` or `auto` to disable, else the mounted drafter is used) | `dflash2` |
| DFlash2 draft count | `serving.speculative.numTokens` (informational; set by the drafter, not a serve flag) | `7` |
| `PARALLEL` | `serving.parallelRequests` | `4` |
| `KERNEL_CACHE` | `kernelCache.hostPath.leader` / `.worker` (a subdirectory per image) | empty (emptyDir: kernels compile on every start) |
| anything else | `serving.extraArgs`, `serving.extraEnv` | empty |

`serve.sh` maps these onto the TensorFold `serve` CLI (`--context`, `--max-tokens`,
`--kv-dtype`, `--drafter`, `--parallel`, `--thinking`/`--no-thinking`, `--vision`)
and sets `TF_GLM_KV=fp8` for the exact FP8 KV cache (upstream passes it as an env
switch, not a `--kv-dtype` value). It serves the mounted checkpoint and (when a
drafter is configured) the mounted DFlash2 drafter with `HF_HUB_OFFLINE=1`, so no
network is needed at start.

## Ansible inventory <-> chart values

| Inventory var | Chart value |
| --- | --- |
| `gpu_fabric_interface` | `topology.fabric.interface` |
| `gpu_fabric_rdma_device` | `topology.fabric.rdmaDevice` |
| `gpu_fabric_address` (host) | `topology.fabric.masterAddr` (leader) / `workerAddr` (worker), without `/30` |
| `gpu_rank_label_key` + `gpu_rank` | `topology.rankLabels.key` + `.leader`/`.worker` |
| `gpu_models_dir` | parent of `weights.hostPath.*` |
## Recipe tuning (`tuning.env`)

Upstream `scripts/config.sh` exports these `TF_GLM_*` / `TF_ROCE_*` /
`TENSORFOLD_*` settings to both ranks. The image bakes in none of them, and each
patch's own default is mostly off. The chart therefore renders `tuning.env` on
both ranks with the recipe's values. To override one, set its key in
`tuning.env`. To fall back to the patch default, set it to `null`.

| Recipe knob | Env | Chart default |
| --- | --- | --- |
| `DENSE` | `TF_GLM_DENSE` | `q4` |
| `COMM` | `TF_GLM_COMM` | `roce` |
| (fixed) | `TF_ROCE_WAIT_S` | `300` |
| `DRAFT_POLICY` | `TF_GLM_DFLASH_POLICY` | `fnc7:0.3` |
| `COPY` / `COPY_MAX` | `TF_GLM_COPY_DRAFTS` / `TF_GLM_COPY_MAX` | `1` / `15` |
| `COPY_CODE` | `TF_GLM_WIDE_GRAPHS`, `TF_GLM_COPY_REPLY_MATCH` | `16`, `16` |
| (fixed) | `TF_GLM_MTP` | `auto` |
| `SPLIT` | `TF_GLM_HC_SPLIT`, `TF_GLM_PREFILL_OVERLAP` | `1`, `2` |
| `KDA_CHUNKED` | `TF_GLM_KDA_CHUNKED` | `1` |
| `MULTI_PREFILL` | `TF_GLM_MULTI_PREFILL` | `1` |
| `FILL_BUDGET_MS` / `FILL_DRAFTS` | `TF_GLM_FILL_BUDGET_MS` / `TF_GLM_FILL_DRAFTS` | `200` / `1` |
| (fixed) | `TF_GLM_L2PF`, `TF_GLM_EXL3_LOADS` | `1`, `nc` |
| (fixed) | `TF_GLM_MULTI_LONE` | `0` |
| `SHARED_PREFIX` | `TF_GLM_SHARED_PREFIX` | `1` |
| (fixed) | `TF_GLM_CACHE_ENTRIES` | `32` |
| `KV_POOL_GIB` | `TF_GLM_CACHE_GIB` | `12.5` |
| (fixed) | `TF_GLM_CLEAR_THINKING` | `0` |
| `STREAM_SMOOTH` / `_MS` | `TF_GLM_STREAM_SMOOTH` / `TF_GLM_STREAM_SMOOTH_MS` | `1` / `400` |
| (fixed) | `TENSORFOLD_NO_UPDATE_CHECK` | `1` |

The chart derives these from `serving.parallelRequests`, as the recipe does,
unless `tuning.env` sets them:

| Env | Value |
| --- | --- |
| `TF_GLM_MULTI_WINDOW` | `32`, or `64` past 4 requests |
| `TF_ROCE_MAX_KB` | `512`, or 16 × the window past 32 rows |
| `MEMORY_RESERVE_GIB` → `TENSORFOLD_MEMORY_RESERVE_GIB` | `14.5`, plus 0.95 for each request past 4, plus 0.04 for each row past 32 |
