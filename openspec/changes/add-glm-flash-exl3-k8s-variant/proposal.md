# Proposal: GLM-5.3-Flash-EXL3 on Kubernetes/k3s

## Summary

Port the [TensorFold recipe for GLM-5.3-Flash-EXL3 on two DGX Sparks](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold)
to Kubernetes/k3s with a Helm chart and an Ansible provisioning layer.
Upstream uses Docker Compose with `start.sh`; this variant runs each rank as a
separate Deployment, joined over a direct ConnectX-7 fabric with RoCE RDMA.

## Motivation

- Upstream requires running `./start.sh` from the head node. A Kubernetes
  deployment gives declarative lifecycle management, health probes, rollback,
  and fits into a larger cluster.
- The Ansible layer joins bare DGX Sparks to an existing k3s cluster as GPU
  agents — no control-plane component lands on the Sparks.

## Scope

- Helm chart: two Deployments (leader + worker), ConfigMaps for the entrypoint
  scripts, a Service, optional Ingress, and optional auth Secret.
- Ansible playbooks: agent-only k3s join, GPU runtime check, fabric netplan,
  labels and taint.
- Scripts: prepare-model (weights download), apply (device plugin + chart),
  verify (SSH-based readiness), smoke (k8s-only /v1/models check).
- CI: helm lint/template, shellcheck, embedded script syntax.

## Non-goals

- The serving image itself (build-time patches are baked upstream into
  `ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold`).
- The EXL3 model weights.
- Control-plane management — the cluster must already exist.
- vLLM-style runtime hotfixes (TensorFold uses build-time patches).

## Dependencies

| Component | Source |
| --- | --- |
| Serving image | `ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold:v0.6.0-31557ed1cef6` |
| Model weights | `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` |
| k3s ansible roles | `k3s-io/k3s-ansible` |
| NVIDIA device plugin | `nvdp/nvidia-device-plugin` |