deployment:
  replicas: 2
ingressClass:
  name: traefik
  isDefaultClass: false
api:
  dashboard: false
ports:
  web:
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
service:
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "${RESOURCE_GROUP}"
    service.beta.kubernetes.io/azure-pip-name: "${INGRESS_PUBLIC_IP_NAME}"
  spec:
    type: LoadBalancer
metrics:
  prometheus:
    addEntryPointsLabels: true
    addRoutersLabels: true
    addServicesLabels: true
    service:
      enabled: true
      labels:
        azure-monitor-job: traefik
    serviceMonitor:
      enabled: false
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi