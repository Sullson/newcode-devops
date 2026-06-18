{{/*
Standard chart name / fullname helpers.
*/}}
{{- define "cv-site.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cv-site.fullname" -}}
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

{{- define "cv-site.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to every object.
*/}}
{{- define "cv-site.labels" -}}
helm.sh/chart: {{ include "cv-site.chart" . }}
{{ include "cv-site.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels: the stable subset used by Service / Deployment selectors.
*/}}
{{- define "cv-site.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cv-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
cloudflared labels reuse common labels but override component/name so the
cloudflared Deployment is selected independently from the cv-site app.
*/}}
{{- define "cv-site.cloudflared.selectorLabels" -}}
app.kubernetes.io/name: cloudflared
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "cv-site.cloudflared.labels" -}}
helm.sh/chart: {{ include "cv-site.chart" . }}
{{ include "cv-site.cloudflared.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: ingress
{{- end -}}

{{/*
ServiceAccount name (fixed to cv-site per the workload-identity federation).
*/}}
{{- define "cv-site.serviceAccountName" -}}
{{- default "cv-site" .Values.serviceAccount.name -}}
{{- end -}}

{{/*
In-cluster observability (PUBLIC live-window view): Prometheus + anonymous
Grafana, each selected independently. Azure Managed Prometheus/Grafana remain
the production-grade variant; this is the no-login, browser-reachable view.
*/}}
{{- define "cv-site.prometheus.selectorLabels" -}}
app.kubernetes.io/name: cv-site-prometheus
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "cv-site.prometheus.labels" -}}
helm.sh/chart: {{ include "cv-site.chart" . }}
{{ include "cv-site.prometheus.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: monitoring
{{- end -}}

{{- define "cv-site.grafana.selectorLabels" -}}
app.kubernetes.io/name: cv-site-grafana
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "cv-site.grafana.labels" -}}
helm.sh/chart: {{ include "cv-site.chart" . }}
{{ include "cv-site.grafana.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: dashboard
{{- end -}}
