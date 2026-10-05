# Tasks

## 1. Chart

- [x] `chart/Chart.yaml` — name `glm-tensorfold`, description, keywords
- [x] `chart/values.yaml` — model, topology, serving, auth, probes
- [x] `chart/templates/_helpers.tpl` — TENSORFOLD_* env vars, pod spec
- [x] `chart/templates/deployments.yaml` — leader + worker
- [x] `chart/templates/configmaps.yaml` — serve.sh + wait-for-worker.sh
- [x] `chart/templates/service.yaml` — port 8888
- [x] `chart/templates/ingress.yaml` — optional
- [x] `chart/templates/secret.yaml` — optional auth
- [x] `chart/templates/NOTES.txt`
- [x] `chart/files/serve.sh` — TensorFold entrypoint
- [x] `chart/files/wait-for-worker.sh` — init container beacon check
- [x] `chart/ci/test-values.yaml` — placeholder values for CI lint/template

## 2. Ansible

- [x] `ansible/inventory.example.yml` — 2-node GPU group with fabric vars
- [x] `ansible/playbooks/site.yml` — agent-only join, netplan, fabric verify
- [x] `ansible/playbooks/apply.yml` — thin wrapper over scripts/apply.sh
- [x] `ansible/init-vault.sh` — encrypt the k3s join token
- [x] `ansible/requirements.yml` — k3s-ansible + ansible.posix

## 3. Scripts

- [x] `scripts/apply.sh` — device plugin, then chart
- [x] `scripts/prepare-model.sh` — download ~176 GiB checkpoint to both nodes
- [x] `scripts/verify-glm.sh` — SSH-based readiness report
- [x] `scripts/smoke-glm.sh` — k8s-only /v1/models check
- [x] `scripts/check-anchors.sh` — syntax-only (no hotfix anchors)
- [x] `scripts/nvidia-device-plugin-values.yaml` — pinned plugin config

## 4. CI/CD

- [x] `.github/workflows/ci.yml` — lint, template, shellcheck, syntax
- [x] `.github/workflows/release.yml` — git-cliff bump + OCI push
- [x] `.github/dependabot.yml` — weekly action updates

## 5. Documentation

- [x] `README.md`
- [x] `ENVS.md`
- [x] `SYNC.md`
- [x] `CREDITS.md`
- [x] `CONTRIBUTING.md`
- [x] `SECURITY.md`
- [x] `RELEASING.md`
- [x] `CODE_OF_CONDUCT.md`
- [x] `CHANGELOG.md`