{{- define "app.podTemplate" -}}
metadata:
  {{- with .Values.podAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "app.labels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  serviceAccountName: {{ include "app.serviceAccountName" . }}
  {{- with .Values.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  containers:
    - name: {{ .Chart.Name }}
      {{- with .Values.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- with .Values.env }}
      envFrom:
        {{- with .configMapName }}
        - configMapRef:
            name: {{ . }}
        {{- end }}
        {{- with .secretName }}
        - secretRef:
            name: {{ . }}
        {{- end }}
      {{- end }}
      {{- if .Values.telemetry.enabled }}
      env:
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: {{ .Values.telemetry.endpoint | quote }}
        - name: OTEL_METRIC_EXPORT_INTERVAL
          value: "60000"
        - name: OTEL_SEMCONV_STABILITY_OPT_IN
          value: http
        - name: OTEL_POD_UID
          valueFrom:
            fieldRef:
              fieldPath: metadata.uid
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "k8s.pod.uid=$(OTEL_POD_UID),k8s.container.name={{ .Chart.Name }}"
      {{- end }}
      ports:
        - name: http
          containerPort: {{ .Values.service.port }}
          protocol: TCP
      {{- with .Values.livenessProbe }}
      livenessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.readinessProbe }}
      readinessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.volumeMounts }}
      volumeMounts:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- with .Values.volumes }}
  volumes:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
