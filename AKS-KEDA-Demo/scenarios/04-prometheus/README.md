# Scenario 04 — Prometheus Scaler

## Concept

The **Prometheus** scaler lets KEDA query any Prometheus-compatible endpoint and
scale based on the result of a PromQL expression. This enables scaling on **any
application or infrastructure metric** — HTTP request rate, error rate, queue depth
from a custom exporter, business KPIs, and more.

```
HTTP load  ──▶  sample-app  ──▶  exposes /metrics  ──▶  Prometheus scrapes
                                                              │
                                                         KEDA queries Prometheus
                                                         (http_requests_total rate)
                                                              │
                                                    ScaledObject adjusts replicas
```

## Architecture

This scenario uses:
- **`sample-app`** — a simple Go HTTP server that counts requests and exposes Prometheus metrics
  at `/metrics` (using the `prom-client` format)
- **Prometheus** — deployed in the `monitoring` namespace via the community Helm chart
- **KEDA Prometheus scaler** — queries `sum(rate(http_requests_total[2m]))` and scales
  when RPS exceeds the threshold

> **With AKS + Azure Monitor Managed Prometheus** you can point KEDA at the
> Azure Monitor workspace endpoint instead. See the note at the bottom of this README.

## Files

| File | Description |
|---|---|
| `01-sample-app.yaml` | HTTP app that exposes Prometheus metrics |
| `02-service.yaml` | ClusterIP Service for the app + a ServiceMonitor |
| `03-scaled-object.yaml` | ScaledObject querying the in-cluster Prometheus |
| `04-load-generator-job.yaml` | Job that fires 5000 HTTP requests to trigger scaling |

## Prerequisites — Install Prometheus

```bash
# Add Prometheus community Helm chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack in the monitoring namespace
helm upgrade --install kube-prometheus \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --wait

# Verify Prometheus is running
kubectl get pods -n monitoring
```

## Steps

```bash
# 1. Deploy the sample app, service, and ScaledObject
kubectl apply -f scenarios/04-prometheus/ -n keda-demo

# 2. Check initial replica count (1 — minReplicaCount)
kubectl get deployment sample-app -n keda-demo

# 3. Watch pods in a second terminal
kubectl get pods -n keda-demo -w

# 4. Run the load generator to drive requests
kubectl apply -f scenarios/04-prometheus/04-load-generator-job.yaml -n keda-demo

# 5. Watch KEDA scale out as RPS climbs
kubectl describe scaledobject prometheus-scaler -n keda-demo

# 6. After load stops, watch replicas scale back down
kubectl get deployment sample-app -n keda-demo -w

# 7. Cleanup
kubectl delete -f scenarios/04-prometheus/ -n keda-demo
```

## Scale Logic

- PromQL: `sum(rate(http_requests_total{namespace="keda-demo"}[2m]))`
- `threshold: "10"` — scale 1 replica per 10 req/s
- At 100 req/s → 10 replicas, at 50 req/s → 5 replicas

## Azure Monitor Managed Prometheus (Advanced)

If your AKS cluster has Azure Monitor managed Prometheus enabled, replace the
`serverAddress` with your Azure Monitor workspace query endpoint:

```yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: "https://<workspace>.australiaeast.prometheus.monitor.azure.com"
      query: "sum(rate(http_requests_total{namespace=\"keda-demo\"}[2m]))"
      threshold: "10"
    authenticationRef:
      name: azure-monitor-auth    # TriggerAuthentication with AAD token
```
