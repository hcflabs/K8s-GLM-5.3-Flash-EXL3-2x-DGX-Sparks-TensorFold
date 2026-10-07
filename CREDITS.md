# Credits

This repo is a Kubernetes/k3s variant of
[MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold)
(MIT, Copyright (c) Mia's AI Lab). The TensorFold patches under the upstream
repo's `patches/` directory are build-time and are baked into the serving image;
this chart uses the published image directly.

Upstream credits (see its `CREDITS.md`):

- **Mia's AI Lab** — the TensorFold recipe and EXL3 quantization.
- **incoai** — DFlash2 speculative decoder (`incoai/GLM-5.3-Flash-DFlash2`).
- **ashhart** — TensorFold v0.6.0.
- **Chris Scott** ([chriswritescode-dev](https://github.com/chriswritescode-dev)) — root commit of the upstream vLLM recipe.

## Dependencies

| Component | Used for | License / source |
| --- | --- | --- |
| [`k3s-io/k3s-ansible`](https://github.com/k3s-io/k3s-ansible) | agent-only node join (`prereq`, `k3s_agent`) | Apache-2.0 |
| [`ansible.posix`](https://github.com/ansible-collections/ansible.posix) | host config modules | GPL-3.0 |
| `ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold` | prebuilt serving image (TensorFold v0.6.0 + GB10 kernels + 82 patches, v1.8) | miaai-lab, see image page |
| [NVIDIA k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) | advertises `nvidia.com/gpu` | Apache-2.0 |
| [`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold`](https://huggingface.co/Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold) | default checkpoint (EXL3 4bpw, ~176 GB) | see model card |
| [`incoai/GLM-5.3-Flash-DFlash2`](https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2) | speculative decoding drafter | see model card |

This repo's own files are MIT (see `LICENSE`).