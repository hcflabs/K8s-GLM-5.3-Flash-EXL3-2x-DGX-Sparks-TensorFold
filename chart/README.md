# glm-tensorfold chart

Serves GLM-5.3-Flash-EXL3 tensor-parallel (TP=2) across two DGX Spark
nodes with TensorFold v0.6.0: a leader Deployment (rank 0, serves `:8888`) and
a worker Deployment (rank 1). Prerequisites: both nodes joined with the rank
labels and GPU taint, the fabric up, weights on both nodes, and the NVIDIA
device plugin installed. See the top-level README for the full flow.

Release name matters: resources are named `<release>-glm-tensorfold-*` unless the
release name already contains `glm-tensorfold` or `fullnameOverride` is set.

## Install

From a checkout:

```bash
helm upgrade --install glm-tensorfold ./chart -n tensorfold --create-namespace -f my-values.yaml
```

From OCI (published on tag):

```bash
helm upgrade --install glm-tensorfold oci://ghcr.io/<owner>/charts/glm-tensorfold \
  --version <version> -n tensorfold --create-namespace -f my-values.yaml
helm pull oci://ghcr.io/<owner>/charts/glm-tensorfold --version <version>
```

Via k3s's built-in helm-controller (apply on the cluster):

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: glm-tensorfold
  namespace: kube-system
spec:
  chart: oci://ghcr.io/<owner>/charts/glm-tensorfold
  version: <version>   # see RELEASING.md
  targetNamespace: tensorfold
  createNamespace: true
  valuesContent: |-
    topology:
      fabric: {masterAddr: <leader-ip>, workerAddr: <worker-ip>, interface: <netdev>, rdmaDevice: <rdma-dev>}
    weights:
      hostPath: {leader: <path>, worker: <path>}
```

## Minimal values

Fabric addressing and weights paths are **required** (no site-specific
defaults; rendering fails without them). Everything else has an upstream-derived
default (`values.yaml` documents every key):

```yaml
topology:
  fabric: {masterAddr: <leader-ip>, workerAddr: <worker-ip>, interface: <netdev>, rdmaDevice: <rdma-dev>}
weights:
  hostPath: {leader: <path-to-checkpoint>, worker: <path-to-checkpoint>}
auth:
  existingSecret: my-api-key      # omit for an unauthenticated /v1
ingress:
  className: traefik
  hosts: [glm.example.com]        # omit for Service-only exposure
```

## Test

`scripts/check-anchors.sh` (repo root) syntax-checks every embedded script;
CI runs it on each PR. Lint/template locally with
`helm lint chart -f chart/ci/test-values.yaml`.