# Upstream sync

Derived from `MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` (read-only git
remote `upstream`).

- **Pinned upstream ref:** `v1.4` (recipe v1.4, TensorFold v0.6.0, 70 patches)
- **Policy:** the upstream repo applies 70 build-time patches to TensorFold v0.6.0;
  the resulting image is published at `ghcr.io/miaai-lab/tensorfold-glm53`.
  This chart uses that image directly; there are no vendored runtime hotfixes.

## Image and serving

| Chart file | Origin |
| --- | --- |
| `chart/files/serve.sh` | adapted from upstream `start.sh` for Kubernetes |
| `chart/files/wait-for-worker.sh` | adapted from upstream beacon logic in `start.sh` |

The upstream `start.sh` handles: image pull, weights download, worker beacon,
TensorFold launch on both ranks, and warmup. This chart splits those concerns:
the Ansible layer handles node setup, `prepare-model.sh` downloads weights, and
`serve.sh` handles the beacon + launch inside the container.

## Patch set

The upstream image bakes in 70 patches (65 for TP=2, 3 for TP=3 experimental,
1 for up to 8 parallel requests, 1 for stopping serial requests). See the
upstream repo's `patches/` directory. When the image is bumped, update the
`image.tag` and `appVersion` in the chart to match.