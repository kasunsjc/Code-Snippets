# Rendered by deploy.sh via `envsubst` before `helm upgrade --install harbor`.
# Placeholders: ${HARBOR_FQDN}
# A separate HARBOR_OIDC_SETTINGS_JSON token (built in deploy.sh, not listed
# here to avoid envsubst expanding it into this comment) is appended inside
# core.configureUserSettings below when OIDC SSO is enabled.
#
# This is a "basic" Harbor install: bundled/internal database, redis and
# trivy (no external Postgres/Redis/object storage), persistence on the AKS
# default storage class (managed-csi).

# managed-csi (Azure Disk) only supports ReadWriteOnce. jobservice/registry
# mount RWO PVCs, so a RollingUpdate leaves the new pod stuck in
# ContainerCreating (Multi-Attach error) waiting for the old pod's volume to
# detach. Recreate terminates the old pod first.
updateStrategy:
  type: Recreate

expose:
  # TLS is terminated by Traefik's IngressRoute, matching the reference
  # Harbor deployment. Harbor receives HTTP on its internal ClusterIP service.
  type: clusterIP
  tls:
    enabled: false
  clusterIP:
    name: harbor
    ports:
      httpPort: 80
      httpsPort: 443

externalURL: https://${HARBOR_FQDN}

internalTLS:
  enabled: false

persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry:
      storageClass: managed-csi
      size: 50Gi
      accessMode: ReadWriteOnce
    database:
      storageClass: managed-csi
      size: 5Gi
      accessMode: ReadWriteOnce
    redis:
      storageClass: managed-csi
      size: 1Gi
      accessMode: ReadWriteOnce
    trivy:
      storageClass: managed-csi
      size: 5Gi
      accessMode: ReadWriteOnce
    jobservice:
      jobLog:
        storageClass: managed-csi
        size: 1Gi
        accessMode: ReadWriteOnce

# Azure Monitor managed Prometheus scrapes Harbor via its own ServiceMonitor
# (harbor-azure-monitor-servicemonitor.yaml, azmonitoring.coreos.com/v1).
# Keep the chart's own ServiceMonitor disabled - it uses the OSS
# monitoring.coreos.com/v1 API group, which Azure Monitor does not watch.
metrics:
  enabled: true
  serviceMonitor:
    enabled: false

registry:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

core:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

  # CONFIG_OVERWRITE_JSON caveat: once this is set, ALL Harbor user-scope
  # settings (including auth_mode) become read-only in the Harbor UI - any
  # further change (e.g. enabling OIDC below) must be made here and applied
  # with `helm upgrade`, not through Administration -> Configuration.
  configureUserSettings: |
    {
      "project_creation_restriction": "adminonly",
      "token_expiration": 30,
      "session_timeout": 60,
      "robot_name_prefix": "robot$",
      "robot_token_duration": 30,
      "read_only": false,
      "notification_enable": true,
      "scanner_skip_update_pulltime": true,
      "audit_log_forward_endpoint": "harbor-audit-forwarder.harbor.svc.cluster.local:10514",
      "disabled_audit_log_event_types": "",
      "skip_audit_log_database": false
      ${HARBOR_OIDC_SETTINGS_JSON}
    }
  # Harbor's local `admin` account always stays DB-authenticated, so it
  # remains a break-glass login after OIDC is enabled.

jobservice:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

portal:
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 250m

trivy:
  enabled: true
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m

database:
  type: internal
  internal:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m

redis:
  type: internal
  internal:
    resources:
      requests:
        memory: 128Mi
        cpu: 100m
      limits:
        memory: 256Mi
        cpu: 250m

cache:
  enabled: true
  expireHours: 24
