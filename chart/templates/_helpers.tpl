{{- define "glm53.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "glm53.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "glm53.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "glm53.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: glm-flash-exl3-tensorfold
{{- end -}}

{{- define "glm53.selectorLabels" -}}
app.kubernetes.io/name: {{ include "glm53.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "glm53.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s:%s@%s" .Values.image.repository .Values.image.tag .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{/* Effective model repo: model.repo, else the Ablit repo when model.ablit, else the published checkpoint. */}}
{{- define "glm53.modelRepo" -}}
{{- $m := .Values.model -}}
{{- $m.repo | default (ternary $m.ablitRepo "Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold" $m.ablit) -}}
{{- end -}}

{{/* Effective model directory name mounted under /models. */}}
{{- define "glm53.modelDir" -}}
{{- $m := .Values.model -}}
{{- $m.dirName | default (base (include "glm53.modelRepo" .)) -}}
{{- end -}}

{{/* True when a mounted DFlash2 drafter is used (anything but none/auto/empty). */}}
{{- define "glm53.useDrafter" -}}
{{- $m := .Values.serving.speculative.method -}}
{{- if and (ne $m "none") (ne $m "auto") (ne $m "") }}true{{ else }}false{{ end -}}
{{- end -}}

{{/* Secret holding the API keys, or empty when /v1 is unauthenticated. */}}
{{- define "glm53.authSecretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else if or .Values.auth.apiKey .Values.auth.apiKeys -}}
{{- printf "%s-api-key" (include "glm53.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/* Per-rank pod environment. Args: dict "root" . "rank" 0|1 */}}
{{- define "glm53.env" -}}
{{- $v := .root.Values -}}
- {name: TENSORFOLD_NODE_RANK, value: {{ .rank | quote }}}
- {name: TENSORFOLD_MASTER_ADDR, value: {{ required "topology.fabric.masterAddr is required" $v.topology.fabric.masterAddr | quote }}}
- {name: TENSORFOLD_WORKER_ADDR, value: {{ required "topology.fabric.workerAddr is required" $v.topology.fabric.workerAddr | quote }}}
- {name: TENSORFOLD_BEACON_PORT, value: {{ $v.topology.fabric.beaconPort | quote }}}
- {name: TENSORFOLD_MASTER_PORT, value: {{ $v.topology.fabric.port | quote }}}
- {name: TENSORFOLD_API_PORT, value: {{ $v.service.port | quote }}}
- {name: TENSORFOLD_MODEL_DIR, value: {{ printf "/models/%s" (include "glm53.modelDir" .root) | quote }}}
- {name: TENSORFOLD_SERVED_MODEL_NAME, value: {{ $v.model.servedName | quote }}}
- {name: TENSORFOLD_MAX_MODEL_LEN, value: {{ $v.serving.maxModelLen | quote }}}
- {name: TENSORFOLD_MAX_TOKENS, value: {{ $v.serving.maxTokens | quote }}}
- {name: TENSORFOLD_KV_CACHE_DTYPE, value: {{ $v.serving.kvCacheDtype | quote }}}
{{- if hasKey $v.serving "thinking" }}
- {name: TENSORFOLD_THINKING, value: {{ $v.serving.thinking | quote }}}
{{- else }}
- {name: TENSORFOLD_THINKING, value: {{ ternary "false" "true" (eq $v.model.ablit true) | quote }}}
{{- end }}
- {name: TENSORFOLD_VISION, value: {{ $v.serving.vision | quote }}}
{{- if eq (include "glm53.useDrafter" .root) "true" }}
- {name: TENSORFOLD_DRAFTER_PATH, value: {{ printf "/models/%s" $v.model.drafter.dirName | quote }}}
{{- end }}
- {name: HF_HUB_OFFLINE, value: "1"}
- {name: TENSORFOLD_SPEC_METHOD, value: {{ $v.serving.speculative.method | quote }}}
- {name: TENSORFOLD_PARALLEL, value: {{ $v.serving.parallelRequests | quote }}}
- {name: TENSORFOLD_EXTRA_ARGS, value: {{ $v.serving.extraArgs | quote }}}
- {name: NCCL_IB_HCA, value: {{ required "topology.fabric.rdmaDevice is required" $v.topology.fabric.rdmaDevice | quote }}}
- {name: NCCL_SOCKET_IFNAME, value: {{ required "topology.fabric.interface is required" $v.topology.fabric.interface | quote }}}
- {name: NCCL_DEBUG, value: "INFO"}
- {name: NCCL_DEBUG_SUBSYS, value: "INIT,NET"}
- {name: PYTORCH_CUDA_ALLOC_CONF, value: "expandable_segments:True"}
- {name: NVIDIA_DISABLE_FORWARD_COMPATIBILITY, value: "1"}
- {name: OMP_NUM_THREADS, value: "20"}
{{- with (include "glm53.authSecretName" .root) }}
- name: TENSORFOLD_API_KEYS
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ if $v.auth.existingSecret }}{{ $v.auth.existingSecretKey }}{{ else }}token{{ end }}
{{- end }}
{{- with $v.serving.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Pod spec shared by both ranks. Args: dict "root" . "rank" 0|1 "component" leader|worker */}}
{{- define "glm53.podSpec" -}}
{{- $v := .root.Values -}}
{{- $isLeader := eq (int .rank) 0 -}}
enableServiceLinks: false
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
{{- with $v.runtimeClassName }}
runtimeClassName: {{ . }}
{{- end }}
{{- with $v.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . | indent 2 }}
{{- end }}
nodeSelector:
  {{ $v.topology.rankLabels.key }}: {{ ternary $v.topology.rankLabels.leader $v.topology.rankLabels.worker $isLeader | quote }}
tolerations:
  - {{ toYaml $v.topology.gpuToleration | nindent 4 | trim }}
{{- if $isLeader }}
initContainers:
  - name: wait-for-worker
    image: {{ include "glm53.image" .root | quote }}
    imagePullPolicy: {{ $v.image.pullPolicy }}
    command: [bash, /etc/tensorfold/wait-for-worker.sh]
    env:
      - {name: TENSORFOLD_WORKER_ADDR, value: {{ required "topology.fabric.workerAddr is required" $v.topology.fabric.workerAddr | quote }}}
      - {name: TENSORFOLD_BEACON_PORT, value: {{ $v.topology.fabric.beaconPort | quote }}}
    volumeMounts:
      - {name: serve, mountPath: /etc/tensorfold}
{{- end }}
containers:
  - name: tensorfold
    image: {{ include "glm53.image" .root | quote }}
    imagePullPolicy: {{ $v.image.pullPolicy }}
    command: [bash, /etc/tensorfold/serve.sh]
{{- if $isLeader }}
    ports:
      - {name: http, containerPort: 8888}
{{- end }}
    env:
{{ include "glm53.env" . | indent 6 }}
    resources:
{{ toYaml $v.resources | indent 6 }}
    securityContext:
      privileged: true
    volumeMounts:
      - {name: models, mountPath: {{ printf "/models/%s" (include "glm53.modelDir" .root) }}, readOnly: true}
{{- if eq (include "glm53.useDrafter" .root) "true" }}
      - {name: drafter, mountPath: {{ printf "/models/%s" $v.model.drafter.dirName }}, readOnly: true}
{{- end }}
      - {name: serve, mountPath: /etc/tensorfold}
      - {name: rdma, mountPath: /dev/infiniband}
      - {name: shm, mountPath: /dev/shm}
{{- if $isLeader }}
    startupProbe:
      httpGet: {path: /health, port: http}
{{ toYaml $v.probes.startup | indent 6 }}
    livenessProbe:
      httpGet: {path: /health, port: http}
{{ toYaml $v.probes.liveness | indent 6 }}
    readinessProbe:
      httpGet: {path: /health, port: http}
{{ toYaml $v.probes.readiness | indent 6 }}
{{- end }}
volumes:
  - name: models
{{- if and (not $isLeader) $v.weights.nfs.enabled }}
    nfs:
      server: {{ required "weights.nfs.server is required when weights.nfs.enabled" $v.weights.nfs.server | quote }}
      path: {{ required "weights.nfs.path is required when weights.nfs.enabled" $v.weights.nfs.path | quote }}
      readOnly: true
{{- else }}
    hostPath:
      path: {{ required (printf "weights.hostPath.%s is required" (ternary "leader" "worker" $isLeader)) (ternary $v.weights.hostPath.leader $v.weights.hostPath.worker $isLeader) | quote }}
      type: Directory
{{- end }}
{{- if eq (include "glm53.useDrafter" .root) "true" }}
  - name: drafter
    hostPath:
      path: {{ required (printf "weights.drafter.hostPath.%s is required when a drafter is used" (ternary "leader" "worker" $isLeader)) (ternary $v.weights.drafter.hostPath.leader $v.weights.drafter.hostPath.worker $isLeader) | quote }}
      type: Directory
{{- end }}
  - name: serve
    configMap:
      name: {{ include "glm53.fullname" .root }}-serve
  - name: rdma
    hostPath:
      path: /dev/infiniband
      type: Directory
  - name: shm
    emptyDir:
      medium: Memory
      sizeLimit: {{ $v.shm.sizeLimit }}
{{- end -}}