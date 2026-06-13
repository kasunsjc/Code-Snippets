# Scenario 03 — Prometheus Scaler (Azure Managed Prometheus)

## Concept

The **Prometheus** scaler lets KEDA query any Prometheus-compatible endpoint and
scale based on the result of a PromQL expression. This enables scaling on **any
application or infrastructure metric** — HTTP request rate, error rate, queue depth
from a custom exporter, business KPIs, and more.

```
HTTP load  ──▶  sample-app  ──▶  exposes /metrics  ──▶  Azure Managed Prometheus scrapes
                                                              │
                                                         KEDA queries Azure Monitor workspace
                                                         (http_requests_total rate)
                                                              │
                                                    ScaledObject adjusts replicas
```

## Architecture

This scenario uses:
- **`sample-app`** — a simple Go HTTP server that counts requests and exposes Prometheus metrics
  at `/metrics`
- **Azure Managed Prometheus** — deployed via Bicep, collects metrics from the cluster through
  the Azure Monitor agent (no Helm required)
- **KEDA Prometheus scaler** — queries `sum(rate(http_requests_total[2m]))` against the Azure
  Monitor workspace query endpoint and scales when RPS exceeds the threshold

## Files

| File | Description |
|---|---|
| `00-trigger-auth.yaml` | Secret + TriggerAuthentication for Azure Managed Prometheus auth |
| `01-sample-app.yaml` | HTTP app that exposes Prometheus metrics |
| `02-service.yaml` | ClusterIP Service for the app + a PodMonitor |
| `03-scaled-object.yaml` | ScaledObject querying Azure Managed Prometheus |
| `04-load-generator-job.yaml` | Job that fires 5000 HTTP requests to trigger scaling |

## Prerequisites

The Bicep deployment already provisions Azure Managed Prometheus and wires it to the AKS
cluster via a Data Collection Rule. You only need to:

1. **Get the Prometheus query endpoint** from the Bicep output:

```bash
PROMETHEUS_ENDPOINT=$(az deployment group show \
  --resource-group rg-aks-keda-demo \
  --name aks-keda-deployment \
  --query "properties.outputs.prometheusQueryEndpoint.value" \
  --output tsv)

echo "Prometheus endpoint: $PROMETHEUS_ENDPOINT"
```

2. **Update `03-scaled-object.yaml`** — replace `<PROMETHEUS_QUERY_ENDPOINT>` with the value above.

3. **Populate the bearer token** for KEDA to authenticate against Azure Managed Prometheus:

```bash
TOKEN=$(az account get-access-token \
  --resource https://prometheus.monitor.azure.com \
  --query accessToken -o tsv)

kubectl create secret generic azure-managed-prometheus-secret \
  --namespace keda-demo \
  --from-literal=bearerToken="$TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

> **Note:** Access tokens expire in ~1 hour. For long-running demos, re-run the command above
> to refresh the token.

## Steps

```bash
# 1. Populate the bearer token (see Prerequisites above)

# 2. Apply TriggerAuthentication
kubectl apply -f scenarios/03-prometheus/00-trigger-auth.yaml

# 3. Update 03-scaled-object.yaml with the Prometheus endpoint, then deploy
kubectl apply -f scenarios/03-prometheus/01-sample-app.yaml
kubectl apply -f scenarios/03-prometheus/02-service.yaml
kubectl apply -f scenarios/03-prometheus/03-scaled-object.yaml

# 4. Check initial replica count (1 — minReplicaCount)
kubectl get deployment sample-app -n keda-demo

# 5. Watch pods in a second terminal
kubectl get pods -n keda-demo -w

# 6. Run the load generator to drive requests
kubectl apply -f scenarios/03-prometheus/04-load-generator-job.yaml

# 7. Watch KEDA scale out as RPS climbs
kubectl describe scaledobject prometheus-scaler -n keda-demo

# 8. After load stops, watch replicas scale back down
kubectl get deployment sample-app -n keda-demo -w

# 9. View scaling in Azure Managed Grafana
# Open the Grafana URL (printed by deploy.sh) and use the
# "Kubernetes / Workload" dashboard to observe replica count changes

# 10. Cleanup
kubectl delete -f scenarios/03-prometheus/ -n keda-demo
```

## Scale Logic

- PromQL: `sum(rate(http_requests_total{namespace="keda-demo"}[2m]))`
- `threshold: "10"` — scale 1 replica per 10 req/s
- At 100 req/s → 10 replicas, at 50 req/s → 5 replicas

## Viewing Metrics in Grafana

The Bicep deployment deploys an Azure Managed Grafana instance linked to the Prometheus workspace.

1. Open the Grafana URL printed by `deploy.sh`
2. Log in with your Azure AD credentials
3. Navigate to **Dashboards → Azure Managed Prometheus → Kubernetes / Workload**
4. Filter by namespace `keda-demo` to watch KEDA-driven scaling in real time
