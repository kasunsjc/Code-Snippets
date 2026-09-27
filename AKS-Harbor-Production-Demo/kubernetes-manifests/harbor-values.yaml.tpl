expose:
  # TLS is terminated by Traefik's IngressRoute (harbor-ingress-route.yaml.tpl);
  # Harbor receives plain HTTP on its internal ClusterIP service.
  type: clusterIP
  tls:
    enabled: false
  clusterIP:
    name: harbor
    ports:
      httpPort: 80
      httpsPort: 443

externalURL: https://${HARBOR_FQDN}

harborAdminPassword: "${HARBOR_ADMIN_PASSWORD}"

database:
  type: external
  external:
    host: "${POSTGRES_HOST}"
    port: "5432"
    username: "harboradmin"
    password: "${POSTGRES_PASSWORD}"
    coreDatabase: "registry"
    existingSecret: "harbor-database"
    sslmode: require

redis:
  type: external
  external:
    addr: "${REDIS_HOST}:${REDIS_PORT}"
    password: "${REDIS_PASSWORD}"
    existingSecret: "harbor-redis"
    tlsOptions:
      enable: true
  # Azure Managed Redis only exposes DB index 0 (SELECT to any other index
  # fails with "ERR DB index is out of range"), so every subsystem shares it -
  # Harbor namespaces keys per-subsystem internally, so this is safe.
  cacheLayerDatabaseIndex: 0
  jobserviceDatabaseIndex: 0
  registryDatabaseIndex: 0
  coreDatabaseIndex: 0
  trivyAdapterIndex: 0

persistence:
  persistentVolumeClaim:
    registry:
      storageClass: "azurefile-premium-zrs-nfs"
      accessMode: ReadWriteMany
      size: 100Gi

updateStrategy:
  type: RollingUpdate

core:
  replicas: 2
  podDisruptionBudget:
    enabled: true
    minAvailable: 1
  configureUserSettings: |
    {
      ${HARBOR_OIDC_SETTINGS_JSON}
      "audit_log_forward_endpoint": "harbor-audit-forwarder.harbor.svc.cluster.local:10514"
    }

portal:
  replicas: 2

jobservice:
  replicas: 2
  jobLoggers: ["stdout"]
  maxJobWorkers: 10

registry:
  replicas: 2

trivy:
  replicas: 2

internalTLS:
  enabled: true
  certSource: auto

metrics:
  enabled: true
  serviceMonitor:
    enabled: false

cache:
  enabled: true
  redis:
    type: external
