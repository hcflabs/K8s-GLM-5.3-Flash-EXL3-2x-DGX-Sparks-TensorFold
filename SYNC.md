# Upstream sync

Derived from `MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` (read-only git
remote `upstream`).

- **Pinned upstream ref:** `v1.8` (recipe v1.8, TensorFold v0.6.0, 82 patches)
- **Image:** the upstream repo applies 82 build-time patches to TensorFold v0.6.0 and
  publishes the result at `ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold`
  (tag `v0.6.0-31557ed1cef6`, digest `sha256:cbb4b3c662...f12588`). This chart uses
  that image directly; there are no vendored runtime hotfixes.
- **Note:** the upstream *local* docker image is named `tensorfold-glm53`;
  the registry repo is the long form above. The chart `image.repository` uses the
  registry path, not the local name.

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

The upstream image bakes in 82 patches for the v1.8 image
(`v0.6.0-31557ed1cef6`). Notable additions since the pin moved from v1.4:

- **0078** — `_take_over` memory fix: a fresh conversation after a long one no
  longer runs both ranks out of memory (`NV_ERR_NO_MEMORY`).
- **0079** — `TENSORFOLD_GLM_PICTURE_CACHE`: the vision frontend reads a
  request's pictures once instead of on every turn.
- **0080** — Quoted media markers: text that merely quotes a picture span stays
  text.
- **0081** — `TF_GLM_TFCAP`: capacity refusals render once as 429 with
  `Retry-After: 5` (was a bare 503/400).
- **0082** — `TF_GLM_MAX_QUEUED`: cap queue depth for foreground requests.
- **0083** — Delivery abort: a stream whose delivery callback raises frees its
  lane at once.
- **0077 (v1.7.1)** — shared-prefix states go by recency, never as superseded.
- **ABLIT=1 (v1.7)** — the gated Ablit weights on request; `HF_TOKEN` required.
  With `ABLIT=1`, `THINKING` defaults to `0`.

See the upstream repo's `patches/` directory and its `CHANGELOG.md`. When the
image is bumped, update the `image.tag`, `image.digest` (optional pin) and
`appVersion` in the chart to match.

## Not ported (upstream features this chart does not carry yet)

- **DFlash2 drafter install**: upstream serves `dflash2` (patch set) and mounts
  the DFlash2 checkpoint (`incoai/GLM-5.3-Flash-DFlash2`) alongside the model.
  This chart only mounts the main checkpoint (`model.dirName`), so the default
  `serving.speculative.method: dflash2` needs the drafter made available to the
  pod (download it beside the model and add a volume, or set the value to `none`
  to use the checkpoint's own MTP head).
- **`ABLIT=1`**: the gated Ablit weights require `HF_TOKEN` and a repo-level env
  plus a read of the gated files. Not wired as a chart value yet.
- **HF cache / `HF_HUB_OFFLINE`**: upstream serves the model from a local HF
  cache with `HF_HUB_OFFLINE=1`; this chart mounts the raw checkpoint dir.