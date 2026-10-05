# Spec: GLM-5.3-Flash-EXL3 serving

## Deployment topology

Two Deployments (`-leader`, `-worker`), each with `replicas: 1` and `strategy: Recreate`.

| Aspect | Value |
| --- | --- |
| Runtime | TensorFold v0.6.0 |
| Image | `ghcr.io/miaai-lab/tensorfold-glm53` |
| API port | 8888 |
| Beacon port | 25099 |
| TP master port | 25000 |
| Weights | EXL3 4bpw (~176 GiB), hostPath or NFS |
| KV cache | FP8 |
| Spec decoding | DFlash2, 7 tokens |

## Networking

- `hostNetwork: true`
- `privileged: true`
- RDMA device mounted at `/dev/infiniband`
- Shared memory: `64Gi` via `emptyDir { medium: Memory }`

## Probes

- **Startup**: `/health` HTTP, initial delay 180s, period 30s, failure threshold 240 (~2h)
- **Liveness**: `/health` HTTP, period 30s, timeout 15s, failure threshold 10
- **Readiness**: `/health` HTTP, period 15s, timeout 10s, failure threshold 3

## Auth

- Default: unauthenticated (`/v1` open, `/health` always open)
- Opt-in: `auth.existingSecret` (operator-managed) or `auth.apiKey`/`auth.apiKeys` (chart-minted)
- Key injected as `TENSORFOLD_API_KEYS` env var

## Resource requests

- CPU: 2
- Memory: 100Gi
- GPU: 1 (`nvidia.com/gpu`)

## Node selection

- Node label: `node.tensorfold/rank=leader|worker`
- GPU toleration: `nvidia.com/gpu:NoSchedule`
- Runtime class: `nvidia`

## Environment variables

| Variable | Chart value | Required |
| --- | --- | --- |
| `TENSORFOLD_NODE_RANK` | derived (0 or 1) | auto |
| `TENSORFOLD_MASTER_ADDR` | `topology.fabric.masterAddr` | yes |
| `TENSORFOLD_WORKER_ADDR` | `topology.fabric.workerAddr` | yes |
| `TENSORFOLD_MODEL_DIR` | `/models/<model.dirName>` | auto |
| `TENSORFOLD_SERVED_MODEL_NAME` | `model.servedName` | no |
| `TENSORFOLD_MAX_MODEL_LEN` | `serving.maxModelLen` | no |
| `TENSORFOLD_KV_CACHE_DTYPE` | `serving.kvCacheDtype` | no |
| `TENSORFOLD_SPEC_METHOD` | `serving.speculative.method` | no |
| `TENSORFOLD_SPEC_TOKENS` | `serving.speculative.numTokens` | no |
| `TENSORFOLD_PARALLEL` | `serving.parallelRequests` | no |
| `NCCL_IB_HCA` | `topology.fabric.rdmaDevice` | yes |
| `NCCL_SOCKET_IFNAME` | `topology.fabric.interface` | yes |