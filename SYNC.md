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

### DFlash2 drafter

Upstream serves the model with DFlash2 speculative decoding: it downloads the
separate drafter checkpoint `incoai/GLM-5.3-Flash-DFlash2` (pinned revision
`bf582e4e...`, CC BY-NC-ND 4.0 — non-commercial, no derivatives) into the HF
cache on each Spark and launches with `--drafter <snapshot path>`.

This chart downloads and mounts only the main checkpoint
(`prepare-model.sh` fetches `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold`;
`weights.hostPath.*`/`model.dirName` mount just that one directory). So the
default `serving.speculative.method: dflash2` maps to
`--drafter incoai/GLM-5.3-Flash-DFlash2`, which the container cannot find
unless the drafter is made available: download it beside the model and add a
second volume, or set `serving.speculative.method: none` to use the
checkpoint's own MTP head (no extra download, but slower decode — upstream
measures dflash2 ~5-10% faster).

`serving.speculative.numTokens` is informational: TensorFold sets the DFlash2
draft step count from the drafter config / `TF_GLM_*` policy knobs, not from a
`serve` flag.

### ABLIT weights (`ABLIT=1`, upstream v1.7)

Upstream can serve the gated Ablit checkpoint
`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold-Ablit` (revision `57edefd2...`,
the published checkpoint abliterated) instead of the published one. The repo is
**gated**: the account must accept the model's terms, an `HF_TOKEN` is required,
and upstream refuses to start before the token reaches the gated files. With
`ABLIT=1`, `THINKING` defaults to `0` (the Ablit weights answer best directly;
a request can still opt into thinking).

This chart has no `ABLIT` value, no `HF_TOKEN` secret plumbing, and no Ablit
repo selection — `serving.thinking` stays `true` regardless of weights. To
support it later: add a `model.ablit` toggle that overrides `model.repo` with
the Ablit repo id, require and inject an `HF_TOKEN`, and default
`serving.thinking` to `false` when Ablit is selected.

### HF cache / `HF_HUB_OFFLINE`

Upstream serves from a local Hugging Face cache on each Spark
(`HF_HOME` -> `~/.cache/huggingface`, mounted into the container at
`/root/.cache/huggingface`) with `HF_HUB_OFFLINE=1` so the ranks read only the
local cache while the weights load (no network at start). It also keeps
TensorFold's `--snapshot-dir` prefix snapshots in a mounted cache.

This chart downloads the checkpoint to a plain directory (`hf download
--local-dir`, not the HF cache layout) and mounts it at `/models/<dirName>`. It
passes the directory directly to `tensorfold serve <dir>`, so no Hub download
even without `HF_HUB_OFFLINE`, but there is no shared HF cache, no drafter
cache, no `HF_HUB_OFFLINE` guarantee, and no `HF_TOKEN` plumbing for gated
repos.

## Git remote and `gh`

The upstream pin is documented above, and the git remote for it is `upstream`.
Because the checkout then has **two** GitHub remotes (`origin` = hcflabs,
`upstream` = MiaAI-Lab), `gh` resolves commands to the upstream unless told
otherwise. Set the default once in the checkout, or pass `--repo` explicitly:

```bash
git remote add upstream https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
git fetch upstream
gh repo set-default hcflabs/K8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
# ...or always: gh <cmd> --repo hcflabs/K8s-GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
```