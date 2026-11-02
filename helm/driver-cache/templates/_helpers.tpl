{{/*
Expand the name of the chart.
*/}}
{{- define "driver-cache.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "driver-cache.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "driver-cache.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — minimal stable set used by Service and NetworkPolicy.
*/}}
{{- define "driver-cache.selectorLabels" -}}
app.kubernetes.io/name: {{ include "driver-cache.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
