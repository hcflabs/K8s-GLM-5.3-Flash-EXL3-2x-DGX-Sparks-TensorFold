# Design: GLM-5.3-Flash-EXL3 on Kubernetes/k3s

## Runtime model

Two Deployments, one per rank. The leader (rank 0) serves the OpenAI-compatible
API (`:8888`) and has liveness/readiness probes. The worker (rank 1) runs
headless with a beacon that the leader waits for.

```
  ┌─────────────────────────────────────────┐
  │  k3s cluster                            │
  │  ┌──────────────┐  ┌──────────────┐     │
  │  │ leader (rank 0)│  │ worker (rank 1)│  │
  │  │ :8888 (API)   │  │ beacon :25099 │   │
  │  │ torchrun TP=2 │  │ torchrun TP=2 │   │
  │  └──────┬───────┘  └──────┬───────┘     │
  │         │      RDMA/RoCE  │              │
  │         └─────────────────┘              │
  │         ConnectX-7 direct link           │
  └─────────────────────────────────────────┘
```

## Networking

- `hostNetwork: true` — NCCL must bind the fabric device directly.
- A point-to-point ConnectX-7 cable between the Sparks, configured by Ansible
  via netplan (static IP, no DHCP, MTU 9000).
- RoCE v2 with the RDMA device passed through (`/dev/infiniband` volume mount).

## Entrypoint

`serve.sh` replaces upstream's `start.sh`. It:
1. Validates required env vars.
2. Worker: opens a TCP beacon on `:25099`.
3. Leader: waits for the worker beacon (10m deadline).
4. Both: launch via `torchrun --nnodes=2 --nproc-per-node=1`.

## Why no runtime hotfixes

TensorFold applies its 70 patches at image build time. The chart uses the
published image directly. There are no runtime hotfix anchors to validate,
so CI is simpler (no `anchors` job).

## Secrets

- `/v1` is unauthenticated by default (matches upstream).
- `auth.existingSecret` or `auth.apiKey(s)` enable bearer-token auth.
- k3s join tokens are vault-encrypted in Ansible (`ansible-vault`).
- API keys are injected as env vars via Kubernetes Secrets, never in ConfigMaps.