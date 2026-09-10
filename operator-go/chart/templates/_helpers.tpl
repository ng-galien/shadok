{{- define "shadok.name" -}}
{{- if .Values.fullnameOverride -}}{{ .Values.fullnameOverride | trunc 54 | trimSuffix "-" }}{{- else -}}{{ printf "%s-%s" .Release.Name (default .Chart.Name .Values.nameOverride) | trunc 54 | trimSuffix "-" }}{{- end -}}
{{- end -}}
{{- define "shadok.componentName" -}}{{ include "shadok.name" .root }}{{ if eq .component "gateway" }}-gateway{{ end }}{{- end -}}
{{- define "shadok.image" -}}
{{- if kindIs "string" .image -}}{{ .image }}{{- else if .image.digest -}}{{ .image.repository }}@{{ .image.digest }}{{- else -}}{{ .image.repository }}:{{ default .defaultTag .image.tag }}{{- end -}}
{{- end -}}
{{- define "shadok.serviceAccount" -}}
{{- $account := index .root.Values.serviceAccounts .component -}}
{{- default (include "shadok.componentName" .) $account.name -}}
{{- end -}}
{{- define "shadok.labels" -}}
{{- $standard := dict "helm.sh/chart" (printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_") "app.kubernetes.io/name" .root.Chart.Name "app.kubernetes.io/instance" (include "shadok.componentName" .) "app.kubernetes.io/component" .component "app.kubernetes.io/version" .root.Chart.AppVersion "app.kubernetes.io/managed-by" .root.Release.Service -}}
{{ toYaml (mergeOverwrite (deepCopy .root.Values.commonLabels) $standard) }}
{{- end -}}
