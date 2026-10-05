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
| `MAX_CONTEXT` | `serving.maxModelLen` | `1048576` |
| `KV_CACHE_DTYPE` | `serving.kvCacheDtype` | `fp8` |
| `DRAFTER` (spec method) | `serving.speculative.method` | `dflash2` |
| `DRAFT_TOKENS` | `serving.speculative.numTokens` | `7` |
| `PARALLEL` | `serving.parallelRequests` | `4` |
| anything else | `serving.extraArgs`, `serving.extraEnv` | empty |

## Ansible inventory <-> chart values

| Inventory var | Chart value |
| --- | --- |
| `gpu_fabric_interface` | `topology.fabric.interface` |
| `gpu_fabric_rdma_device` | `topology.fabric.rdmaDevice` |
| `gpu_fabric_address` (host) | `topology.fabric.masterAddr` (leader) / `workerAddr` (worker), without `/30` |
| `gpu_rank_label_key` + `gpu_rank` | `topology.rankLabels.key` + `.leader`/`.worker` |
| `gpu_models_dir` | parent of `weights.hostPath.*` |