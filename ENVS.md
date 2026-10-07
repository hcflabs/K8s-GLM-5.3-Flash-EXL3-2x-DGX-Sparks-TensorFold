# Upstream knobs -> chart values

Upstream configures the TensorFold recipe through environment variables in
`start.sh` / `scripts/config.sh`. Each knob below maps to exactly one chart
value.

## Serving and topology

| Upstream knob / flag | Chart value | Default |
| --- | --- | --- |
| `MODEL_REPO` | `model.repo` (download: `scripts/prepare-model.sh`) | `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` |
| `SERVED_MODEL_NAME` | `model.servedName` | `GLM-5.3-Flash-EXL3` |
| HF cache path | `weights.hostPath.leader` / `.worker` | **required** |
| `WORKER_WEIGHTS=nfs` | `weights.nfs.{enabled,server,path}` | off |
| `HEAD_IP` (leader fabric) | `topology.fabric.masterAddr` | **required** |
| `WORKER_IP` (worker fabric) | `topology.fabric.workerAddr` | **required** |
| `CX7_IF` | `topology.fabric.interface` | **required** |
| `CX7_RDMA` | `topology.fabric.rdmaDevice` | **required** |
| torch distributed port | `topology.fabric.port` | `25000` |
| rank node selection | `topology.rankLabels.*` | `node.tensorfold/rank=leader\|worker` |
| `CONTEXT` | `serving.maxModelLen` | `1048576` |
| `MAX_TOKENS` | `serving.maxTokens` | `4096` |
| `KV` (fp8 / bf16 / int8 / int4) | `serving.kvCacheDtype` | `fp8` |
| `THINKING` | `serving.thinking` | `true` |
| `VISION` | `serving.vision` | `false` |
| drafter | `serving.speculative.method` (a repo id, `none`, or `auto`) | `dflash2` |
| DFlash2 draft count | `serving.speculative.numTokens` (informational; set by the drafter, not a serve flag) | `7` |
| `PARALLEL` | `serving.parallelRequests` | `4` |
| anything else | `serving.extraArgs`, `serving.extraEnv` | empty |

`serve.sh` maps these onto the TensorFold `serve` CLI (`--context`, `--max-tokens`,
`--kv-dtype`, `--drafter`, `--parallel`, `--thinking`/`--no-thinking`, `--vision`)
and sets `TF_GLM_KV=fp8` for the exact FP8 KV cache (upstream passes it as an env
switch, not a `--kv-dtype` value).

## Ansible inventory <-> chart values

| Inventory var | Chart value |
| --- | --- |
| `gpu_fabric_interface` | `topology.fabric.interface` |
| `gpu_fabric_rdma_device` | `topology.fabric.rdmaDevice` |
| `gpu_fabric_address` (host) | `topology.fabric.masterAddr` (leader) / `workerAddr` (worker), without `/30` |
| `gpu_rank_label_key` + `gpu_rank` | `topology.rankLabels.key` + `.leader`/`.worker` |
| `gpu_models_dir` | parent of `weights.hostPath.*` |