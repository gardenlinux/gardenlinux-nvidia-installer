{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "nvidia-installer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nvidia-device-plugin.name" -}}
{{- printf "%s-nvidia-device-plugin" (default .Chart.Name .Values.nameOverride) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}

{{- define "nvidia-installer.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "image-pull-secret" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "image-pull-secrets" -}}
{{- if .Values.imagePullSecret.enabled }}
        - name: {{ template "image-pull-secret" . }}
{{- end }}
{{- with .Values.imagePullSecrets }}
{{- toYaml . | nindent 8 }}
{{- end }}
{{- if and (not .Values.imagePullSecret.enabled) (empty .Values.imagePullSecrets) -}}
[]
{{- end }}
{{- end -}}

{{- define "service-account" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nvidia-device-plugin.fullname" -}}
{{- $name := default "nvidia-device-plugin" .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
