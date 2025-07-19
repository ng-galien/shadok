{{/*
Expand the name of the chart.
*/}}
{{ define "operator.name" -}}
{{ default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "operator.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{ define "operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{ define "operator.labels" -}}
helm.sh/chart: {{ include "operator.chart" . }}
{{ include "operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{ define "operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{ define "operator.serviceAccountName" -}}
{{- default (include "operator.fullname" .) .Values.serviceAccount.name }}
{{- end }}

{{/*
Create the name of the cluster role to use
*/}}
{{ define "operator.clusterRoleName" -}}
{{- default (include "operator.fullname" .) .Values.clusterRole.name }}
{{- end }}

{{/*
Create the name of the cluster role binding to use
*/}}
{{ define "operator.clusterRoleBindingName" -}}
{{- default (include "operator.fullname" .) .Values.clusterRoleBinding.name }}
{{- end }}

{{/*
Create the name of service
*/}}
{{ define "operator.serviceName" -}}
{{- default (include "operator.fullname" .) .Values.service.name }}
{{- end }}

{{/*
Create the name of the certificate
*/}}
{{ define "operator.certificateName" -}}
{{- default (include "operator.fullname" .) .Values.webhook.certificate.name }}
{{- end }}

{{/*
Create the name of the certificate secret
*/}}
{{ define "operator.certificateSecretName" -}}
{{- .Values.webhook.certificate.secretName | default "shadock-webhook-server-cert" }}
{{- end }}








