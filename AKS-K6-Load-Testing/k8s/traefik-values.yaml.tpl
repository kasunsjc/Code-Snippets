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
    buckets: "0.005,0.01,0.025,0.05,0.1,0.2,0.5,1,2,5"
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