# Upstream sync

Derived from `MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` (read-only git
remote `upstream`).

- **Pinned upstream ref:** `main` at `3fd60df` (after v1.10; TensorFold v0.6.0, 107 patches)
- **Image:** the upstream repo applies 107 build-time patches to TensorFold v0.6.0 and
  publishes the result at `ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold`
  (tag `v0.6.0-e66c657a433d`, digest `sha256:14b5072e8e...4399ccf`, arm64). This chart
  uses that image directly; there are no vendored runtime hotfixes. The image is the one
  upstream `main`'s `scripts/config.sh` pins (PR #131). Upstream's CHANGELOG still lists
  these patches as Unreleased: no release branch carries them yet. The last release is
  `release/v1.10` (`v0.6.0-a1897d591f70`, 96 patches). To go back to it, set `image.tag`.
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

The upstream image bakes in 107 patches for the pinned image
(`v0.6.0-e66c657a433d`). Notable additions since the pin moved from v1.4:

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

Added by v1.9 and v1.10 (82 -> 96 patches):

- **0084** — the Anthropic Messages API (`/v1/messages`).
- **0085, 0086** — long-context decode and cold prefill: the DSA indexer's split
  top-k selection and the prompt-scores loop no longer grow with context.
- **0087** — `DISPLAY_KV_BACKEND` (`drm` default, `dispram` for kindling
  spark-os); the GB10 display reservation of patch 0072.
- **0088** — the spill tier: kept prompt states go to local disk and come back
  instead of a new prefill, also after a clean restart. Off unless `SPILL_GIB`.
- **0089** — kept-state limits (`TF_GLM_KEPT_BYTES_GIB`, `TF_GLM_KEEP_PER_CHAT`),
  both off by default: caps the memory the states own outside the pool, and how
  many turn-boundary states one conversation can hold.
- **0090** — the decode expert kernel's launch order (`TF_GLM_EXL3_DEC_ORDER`).
- **0091** — `TF_GLM_LOOP_GUARD=1` (off by default): a think block that collapsed
  into a repeated character is cut instead of served.
- **0092** — the drafter checks its candidate ids against the vocabulary.
- **0093** — `/v1/responses` accepts OpenAI's `include`.
- **0094** — chunked request bodies (`Transfer-Encoding: chunked`).
- **0095** — a streamed request is refused at saturation before its 200 goes out,
  so it gets the same 429 + `Retry-After` as a non-streamed one.
- **0096** — `TF_GLM_EFFORT_TAIL=1` (off by default): renders the reasoning-effort
  line at the tail so switching effort or thinking keeps the prompt cache.
- **0097** — `TF_GLM_CACHE_SHARE_PCT`: the kept-state count as a share of the
  pool's budget, since each state is also a reservation of it.
- **`TENSORFOLD_NUCLEUS_UNION=1`** (config.sh, no patch) — sampled decode tests
  the ranks' candidates together instead of one rank alone, which used to gather
  and sort the whole vocabulary on the CPU (~15 tok/s against greedy's ~58).

Added on upstream `main` after v1.10 (96 -> 107 patches, all the same bits as before
unless noted; most by BadAd84):

- **0098** — the drafter and vision loaders copy each tensor out of the safetensors
  mmap first, so the server starts on kindling spark-os (64 KiB pages).
- **0099** — prompts are tokenized with Python's GIL released: no stall of the other
  streams at a long request's start.
- **0100** — the next DFlash2 draft pass starts at the end of a round
  (`TF_GLM_DRAFT_PRELAUNCH=0` turns it off).
- **0101, 0105, 0106** — a prompt chunk's pool selection in one pass, its indexer
  scoring and its sparse attention in CUDA (`TF_GLM_SCORES_CUDA=0`,
  `TF_GLM_ONEPASS_CUDA=0`: Triton). The sparse-attention kernel applies at 17-24 heads
  a rank (three Sparks). Two Sparks (32 heads) keep Triton.
- **0102** — a prompt chunk's dense projections on a faster tile (`TF_GLM_PROMPT_TILE=0`).
- **0103** — small decode matmuls without thread-block clusters
  (`TF_GLM_QMM_CLUSTERS=1`: as before). The kernel extension is renamed
  `tensorfold_qmm_v5`, so a new kernel-cache folder is needed. The chart already keeps
  one per image.
- **0104, 0108** — three-Spark decode attention tiles and latent attention in CUDA
  (`TF_GLM_SEG_CHUNKS_CUDA=0`: Triton).
- **0107** — the decode indexer, twice as fast with four agents
  (`TF_GLM_SEG_SCORES_CUDA=0` / `TF_GLM_SEG_SELECT_FLOOR=0`: the old path).
- **`FILL_ROWS=2048`** (config.sh, no patch) — `TF_GLM_FILL_ROWS`, carried in
  `tuning.env`: a prompt that fills while other replies decode does so in 2,048-row
  chunks instead of TensorFold's 1,024, ~10-14% sooner.

The CUDA kernels of 0105-0108 are built when the engine starts. If the build fails,
the Triton kernel serves (logged once), so the first start on a new image takes longer.

The v1.10 launcher also probes a second rail from its own port before using it
(`scripts/nodes.sh` `probe_rails`) and drops a rail that cannot reach the peer.
That check has no chart counterpart: here the fabric is Ansible's, and
`playbooks/site.yml` pings each rail (see the top-level repo) instead.

See the upstream repo's `patches/` directory and its `CHANGELOG.md`. When the
image is bumped, update the `image.tag`, `image.digest` (optional pin) and
`appVersion` in the chart to match.

## Port status vs upstream

The runtime gaps that were not carried are now ported. The chart serves the
same published image the upstream bakes and carries the DFlash2 drafter and the
Ablit option:

### DFlash2 drafter (ported)

`prepare-model.sh --drafter` downloads `incoai/GLM-5.3-Flash-DFlash2` (pinned
revision `bf582e4e...`; CC BY-NC-ND 4.0 — non-commercial, no derivatives)
beside the checkpoint. The chart mounts it (`weights.drafter.hostPath.*`) and
`serve.sh` passes `--drafter <path>`. To serve without it (the checkpoint's
own MTP head; slower decode, upstream measures dflash2 ~5-10% faster) set
`serving.speculative.method: none` and `serving.parallelRequests: 1`. The MTP head serves
one request at a time, so the chart refuses to render `none` with more, as upstream's
`start.sh` refuses `DRAFTER=mtp` with `PARALLEL` above 1.

### Launch details (ported)

- `VISION_URLS=1` (`--vision-urls`): `serving.visionUrls`, with `serving.vision`.
- `--ulimit stack=67108864`: Kubernetes has no per-pod ulimit, so `serve.sh` runs
  `ulimit -s 65536` before the exec. It logs a warning when the runtime's hard
  limit is lower. The rest of upstream's `docker run` flags map to the pod spec
  (host network, a privileged container in place of `IPC_LOCK` and
  `memlock=-1`, `/dev/infiniband`, `/dev/shm`).

`serving.speculative.numTokens` is informational: TensorFold sets the DFlash2
draft step count from the drafter config / `TF_GLM_*` policy knobs, not from a
`serve` flag.

### Ablit weights (ported)

`prepare-model.sh --ablit` downloads the gated
`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold-Ablit` (revision `57edefd2...`)
and requires `HF_TOKEN`. Set `model.ablit: true` and the chart defaults
`model.repo`/`model.dirName` to the Ablit repo and `serving.thinking` to `false`
(the Ablit weights answer best directly).

### Recipe tuning (ported)

Upstream `scripts/config.sh` exports about 30 `TF_GLM_*` / `TF_ROCE_*` /
`TENSORFOLD_*` settings, and the published speed numbers depend on them: q4
dense weights, RoCE all-gathers, the draft policy, copy drafts, the prefill
split, multi-prefill, shared-prefix reuse, the L2 prefetch and so on. The image
bakes in none of them, and each patch's own default is mostly off. Before
`tuning.env` existed, this chart served bf16 dense weights over NCCL, with none
of the speed patches turned on.

`tuning.env` now carries the recipe's values, and the chart derives the
`PARALLEL`-dependent ones (window, RoCE size, memory reserve) the way
`config.sh` does. Its `serving.maxTokens` default is the recipe's 32768. The
mapping is in `ENVS.md`. When the pin moves, compare `tuning.env` with what
`config.sh` exports:

```bash
env -i HOME=/tmp PATH="$PATH" bash -c 'source scripts/config.sh >/dev/null 2>&1; env' | grep -E '^(TF_|TENSORFOLD_)' | sort
```

### Kernel cache (ported)

The image compiles its CUDA kernels into `/cache` (`TORCH_EXTENSIONS_DIR`,
`TRITON_CACHE_DIR`). The recipe keeps that directory under `KERNEL_CACHE`, with
one folder per image. `kernelCache.hostPath.*` does the same: a host directory
per rank, with a subdirectory per image tag and digest. When it is empty, the
chart uses an emptyDir, and the kernels compile again on every start.

### Both rails of a port

One QSFP port of a GB10 is two PCIe x4 rails, and each rail has its own netdev
and RoCE device. The recipe addresses both and lists both in `NCCL_IB_HCA`. The
RoCE all-gathers read the same list and use up to two devices. To do the same
here, set `topology.fabric.rdmaDevice` to `dev0,dev1` once both twins carry an
address. `topology.fabric.gidIndex` and `ncclChannels` map to the recipe's
`NCCL_IB_GID_INDEX` and `NCCL_CHANNELS` (4).

### HF cache / `HF_HUB_OFFLINE` (adapted)

The chart runs the container with `HF_HUB_OFFLINE=1` and serves the downloaded
checkpoint and drafter directories directly (`tensorfold serve <dir>`), so no
network is needed at start. Upstream instead uses Hugging Face's cache layout
and keeps TensorFold prefix snapshots in a mounted cache; this chart mounts
explicit checkpoint and drafter directories rather than an HF cache.

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