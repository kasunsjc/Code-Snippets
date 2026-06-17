# Scenario 03 — Prometheus Scaler (Azure Managed Prometheus)

## Overview

Scale a Kubernetes Deployment based on **any Prometheus metric** using KEDA's `prometheus` trigger backed by **Azure Managed Prometheus** and **Azure AD Workload Identity** (no expiring bearer tokens).

```
                                     Azure Managed Prometheus
                                    ┌──────────────────────┐
 Load Generator ──▶ sample-app ──▶  │  scrapes /metrics    │
  (Deployment)       (Deployment)   │  via ServiceMonitor  │
                                    └──────────┬───────────┘
                                               │
                                   KEDA queries PromQL every 15s
                                   (Workload Identity → Azure AD token)
                                               │
                                    ┌──────────▼───────────┐
                                    │     ScaledObject      │
                                    │  threshold: 10 req/s  │
                                    │  per replica          │
                                    └──────────┬───────────┘
                                               │
                                         HPA adjusts
                                    sample-app replicas (1–10)
```

## How It Works

1. **sample-app** exposes `http_requests_total` as a Prometheus counter on `/metrics`.
2. **Azure Monitor Agent (AMA)** scrapes the metric via a `ServiceMonitor` CRD (`azmonitoring.coreos.com/v1`) deployed alongside the service.
3. **KEDA** periodically queries Azure Managed Prometheus using the PromQL expression:
   ```promql
   sum(rate(http_requests_total{namespace="keda-demo"}[2m]))
   ```
4. KEDA calculates desired replicas as `ceil(queryResult / threshold)`:
   - 45 req/s → `ceil(45/10)` = **5 replicas**
   - 100 req/s → `ceil(100/10)` = **10 replicas** (max)
   - 0 req/s → **1 replica** (min)
5. Authentication to Azure Managed Prometheus uses **Workload Identity**:
   - Terraform provisions a **User-Assigned Managed Identity** with `Monitoring Data Reader` on the Prometheus workspace.
   - A **Federated Identity Credential** trusts `system:serviceaccount:kube-system:keda-operator` (the KEDA add-on's operator SA).
   - KEDA exchanges the operator's projected SA token for a short-lived Azure AD access token — no secrets or manual token refresh needed.

## Files

| File | Kind | Description |
|------|------|-------------|
| `00-trigger-auth.yaml` | `TriggerAuthentication` | Configures KEDA to use `podIdentity: azure-workload` with the managed identity client ID |
| `01-sample-app.yaml` | `ConfigMap` + `Deployment` | Python HTTP server exposing `http_requests_total` at `/metrics` |
| `02-service.yaml` | `Service` + `ServiceMonitor` | ClusterIP Service + AMA scrape target (`azmonitoring.coreos.com/v1`) |
| `03-scaled-object.yaml` | `ScaledObject` | KEDA trigger — queries Prometheus, threshold 10 req/s per replica |
| `04-load-generator-job.yaml` | `Deployment` | Continuous HTTP load generator — scale replicas to control traffic |

## Terraform-Provisioned Resources

All Azure infrastructure is managed by Terraform (no manual setup):

| Resource | Module | Purpose |
|----------|--------|---------|
| Azure Monitor Workspace (Prometheus) | `modules/monitoring` | Stores scraped metrics |
| Data Collection Rule + Association | `modules/monitoring` + root | Wires AMA → Prometheus workspace |
| Azure Managed Grafana | `modules/monitoring` | Optional visualization |
| User-Assigned Managed Identity | `modules/workload_identity` | KEDA's identity for Prometheus access |
| Federated Identity Credential | `modules/workload_identity` | Trusts `kube-system:keda-operator` SA |
| Role Assignment (Monitoring Data Reader) | `modules/workload_identity` | Grants identity read access to Prometheus workspace |

## Deployment

### Recommended: Using deploy.sh

```bash
./deploy.sh --demo prometheus
```

This runs Terraform (creates all Azure resources), fetches outputs, and applies all manifests with the correct values substituted:
- `{{ PROMETHEUS_QUERY_ENDPOINT }}` → Azure Managed Prometheus query URL
- `{{ PROMETHEUS_WORKLOAD_IDENTITY_CLIENT_ID }}` → Managed Identity client ID

No images need to be built — the sample app uses `python:3.12-slim` directly.

### Manual Deployment

If you prefer to apply manifests individually (infrastructure must already exist):

```bash
# 1. Get Terraform outputs
cd terraform
PROMETHEUS_ENDPOINT=$(terraform output -raw prometheus_query_endpoint)
WI_CLIENT_ID=$(terraform output -raw prometheus_workload_identity_client_id)

# 2. Apply manifests with sed substitution
cd ../scenarios/03-prometheus

for f in 00-trigger-auth.yaml 01-sample-app.yaml 02-service.yaml 03-scaled-object.yaml 04-load-generator-job.yaml; do
  sed -e "s|{{ PROMETHEUS_QUERY_ENDPOINT }}|$PROMETHEUS_ENDPOINT|g" \
      -e "s|{{ PROMETHEUS_WORKLOAD_IDENTITY_CLIENT_ID }}|$WI_CLIENT_ID|g" \
      "$f" | kubectl apply -n keda-demo -f -
done
```

## Testing Scale-Out and Scale-In

The load generator Deployment starts at 1 replica. Each replica sends ~30 concurrent requests per second in a tight loop.

### Generate Load (Scale Out)

```bash
# Scale load generator up — drives ~150 req/s (5 × 30)
kubectl scale deployment load-generator -n keda-demo --replicas=5

# Watch HPA react (updates every 15s)
kubectl get hpa -n keda-demo -w
```

Expected: `sample-app` scales up to 10 replicas (max) within ~30–60 seconds.

### Stop Load (Scale In)

```bash
# Scale load generator to zero
kubectl scale deployment load-generator -n keda-demo --replicas=0

# Watch scale-down (takes ~3-4 minutes)
kubectl get hpa -n keda-demo -w
```

Expected: After the 2-minute PromQL rate window drains + 90s cooldown, `sample-app` scales back to 1 replica.

### Verify Metrics are Flowing

```bash
# Check that KEDA can read the metric
kubectl get scaledobject prometheus-scaler -n keda-demo

# READY=True, ACTIVE=True means it's working
# READY=False → check KEDA operator logs (see Troubleshooting)

# Query the metric directly (requires a valid token)
PROMETHEUS_ENDPOINT=$(terraform -chdir=terraform output -raw prometheus_query_endpoint)
TOKEN=$(az account get-access-token --resource https://prometheus.monitor.azure.com --query accessToken -o tsv)

curl -s -H "Authorization: Bearer $TOKEN" \
  "$PROMETHEUS_ENDPOINT/api/v1/query?query=sum(rate(http_requests_total{namespace=\"keda-demo\"}[2m]))" | python3 -m json.tool
```

## Configuration

### Tuning Parameters

| Parameter | Location | Default | Description |
|-----------|----------|---------|-------------|
| `threshold` | `03-scaled-object.yaml` | `10` | Target req/s per replica. Lower = more aggressive scaling |
| `pollingInterval` | `03-scaled-object.yaml` | `15` | How often (seconds) KEDA queries Prometheus |
| `cooldownPeriod` | `03-scaled-object.yaml` | `90` | Seconds to wait before scaling down after metrics drop |
| `minReplicaCount` | `03-scaled-object.yaml` | `1` | Minimum replicas (set to 0 for scale-to-zero) |
| `maxReplicaCount` | `03-scaled-object.yaml` | `10` | Maximum replicas |
| `[2m]` in query | `03-scaled-object.yaml` | `2m` | PromQL rate window — longer = smoother but slower reaction |
| `interval` | `02-service.yaml` | `15s` | How often AMA scrapes the app |
| `CONCURRENT` | `04-load-generator-job.yaml` | `30` | Requests per loop iteration per load-generator pod |

### Scaling Formula

```
desiredReplicas = ceil( sum(rate(http_requests_total{namespace="keda-demo"}[2m])) / threshold )
```

Clamped to `[minReplicaCount, maxReplicaCount]`.

## Troubleshooting

### KEDA ScaledObject shows READY=False

```bash
# Check ScaledObject conditions
kubectl describe scaledobject prometheus-scaler -n keda-demo

# Check KEDA operator logs
kubectl logs -n kube-system -l app=keda-operator --tail=50 | grep -i "error\|failed"
```

**Common causes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `missing required parameter "serverAddress"` | `{{ PROMETHEUS_QUERY_ENDPOINT }}` not substituted | Re-run `./deploy.sh --demo prometheus` or check `terraform output -raw prometheus_query_endpoint` is non-empty |
| `AADSTS700213: No matching federated identity record` | Federated credential subject mismatch | Ensure Terraform created the credential with subject `system:serviceaccount:kube-system:keda-operator` |
| `Client.Timeout exceeded` | Transient network issue | Usually self-resolves; check KEDA again after 30s |
| `401 Unauthorized` without AADSTS700213 | Missing role assignment | Ensure the managed identity has `Monitoring Data Reader` on the Prometheus workspace |

### Metrics return 0 / no data

```bash
# Check ServiceMonitor is deployed
kubectl get servicemonitor -n keda-demo

# Verify the app is actually receiving traffic
kubectl logs -l app=sample-app -n keda-demo --tail=5

# Check AMA is scraping (look for keda-demo targets)
kubectl port-forward -n kube-system ds/ama-metrics-node 9090:9090
# Then visit http://localhost:9090/targets
```

### HPA shows `<unknown>/10`

This means the external metric hasn't been reported yet. Common during the first 1–2 polling intervals after creation. If it persists:

```bash
# Verify KEDA metrics server is running
kubectl get pods -n kube-system | grep keda-metrics

# Check if the metric is registered
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/keda-demo/s0-prometheus" | python3 -m json.tool
```

## Cleanup

```bash
kubectl delete -f scenarios/03-prometheus/ -n keda-demo
```

Or to remove all demos and infrastructure:

```bash
./cleanup.sh
```

## Scale Logic

- PromQL: `sum(rate(http_requests_total{namespace="keda-demo"}[2m]))`
- `threshold: "10"` — scale 1 replica per 10 req/s
- At 100 req/s → 10 replicas, at 50 req/s → 5 replicas

## Viewing Metrics in Grafana

The Terraform deployment deploys an Azure Managed Grafana instance linked to the Prometheus workspace.

1. Open the Grafana URL printed by `deploy.sh`
2. Log in with your Azure AD credentials
3. Navigate to **Dashboards → Azure Managed Prometheus → Kubernetes / Workload**
4. Filter by namespace `keda-demo` to watch KEDA-driven scaling in real time
