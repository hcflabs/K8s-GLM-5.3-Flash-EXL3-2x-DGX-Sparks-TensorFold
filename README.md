# GLM-5.3-Flash-EXL3 on two DGX Sparks with TensorFold - Kubernetes/k3s

[![ci](https://github.com/MiaAI-Lab/K8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/actions/workflows/ci.yml/badge.svg)](https://github.com/MiaAI-Lab/K8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/MiaAI-Lab/K8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold)](https://github.com/MiaAI-Lab/K8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/releases)
[![chart](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FMiaAI-Lab%2FK8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold%2Fmain%2Fchart%2FChart.yaml&query=%24.version&label=chart&color=0F1689)](chart/Chart.yaml)
[![license](https://img.shields.io/github/license/MiaAI-Lab/K8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold)](LICENSE)

A Helm chart plus an Ansible layer that serve
`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` tensor-parallel (TP=2, 1M-token
context, EXL3 4bpw, FP8 KV cache, DFlash2 speculative decoding) across two
NVIDIA DGX Spark (GB10, arm64) nodes joined to an **existing** k3s cluster,
via TensorFold v0.6.0. A Kubernetes port of
[MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold);
see [`CREDITS.md`](CREDITS.md) and [`SYNC.md`](SYNC.md).

```
chart/      Helm chart (two Deployments + beacon ConfigMaps, Service, optional Ingress)
ansible/    agent-only k3s join, GPU runtime check, fabric netplan + verify, labels/taint
scripts/    prepare-model, apply (device plugin + chart), verify, smoke, check-anchors
cliff.toml  changelog + chart-version rules; releases run in Actions (RELEASING.md)
.github/    CI, the release workflow, issue/PR templates, dependabot
```

## Prerequisites

Two Sparks with `nvidia-container-runtime` installed, a dedicated
point-to-point ConnectX-7 cable between them (find its netdev with `ip -br link`
and its RDMA device under `/sys/class/infiniband`), SSH access, and a reachable k3s
control plane (URL + join token). Control machine: `helm`, `kubectl`,
`ansible-core >= 2.15`.

## Quick start

1. **Provision** (agent-only; no control-plane component lands on the Sparks)

   ```bash
   cd ansible
   ansible-galaxy collection install -r requirements.yml
   cp inventory.example.yml inventory.yml     # edit hosts, api_endpoint, fabric, k3s_version
   K3S_TOKEN=<existing cluster token> ./init-vault.sh
   ansible-playbook playbooks/site.yml --vault-password-file .vault_pass
   # fabric only: --tags gpu_fabric     dry run: --check
   ```

2. **Download weights** on both nodes (~176 GiB each)

   ```bash
   scripts/prepare-model.sh --models-dir /data/models user@spark-leader user@spark-worker
   ```

3. **Apply** the pinned device plugin, then the chart

   ```bash
   scripts/apply.sh -f my-values.yaml          # fabric + weights values are required; see chart/README.md
   ```

4. **Verify**

   ```bash
   scripts/verify-glm.sh --leader user@spark-leader --worker user@spark-worker \
     --leader-fabric-ip <ip> --worker-fabric-ip <ip> --fabric-if <netdev> --rdma-dev <rdma> --model-dir <path>
   scripts/smoke-glm.sh                     # k8s-only /v1/models check
   ```

   Expect `max_model_len: 1048576`. Cold start takes tens of minutes up to ~2 h.
   Check NCCL logs for `NET/IB`; `NET/Socket` means a silent TCP fallback
   (wrong `rdmaDevice`) costing ~2x decode throughput.

Parameter reference: [`ENVS.md`](ENVS.md). Install via OCI or a k3s `HelmChart`:
[`chart/README.md`](chart/README.md).

## Releases

The chart version, changelog, tag, OCI push and GitHub Release are all produced
by the `release` workflow; no release step is done by hand. Run it from the
Actions tab or `gh workflow run release.yml -f bump=auto`. See
[`RELEASING.md`](RELEASING.md).

## Operations

- **No auth by default**: `/v1` is open unless `auth.existingSecret` or `auth.apiKey(s)` is set. `/health` is always open.
- **Image bumps**: the serving image is ghcr.io/miaai-lab/tensorfold-glm53. Check `SYNC.md` for upstream pinning.
- **Rollback**: `helm uninstall glm-tensorfold -n tensorfold` (removes Deployments, Service, Ingress, ConfigMaps, minted Secret). Delete the namespace to drop everything else. Node-side changes (labels, taint, fabric netplan) are idempotent; re-run `site.yml` to re-assert. To remove the device plugin: `helm uninstall nvidia-device-plugin -n gpu`.
- **Debugging**: the Sparks' kubelets are often unreachable from the API server, so `kubectl logs/exec` may fail; use `verify-glm.sh` (SSH) or your log stack.