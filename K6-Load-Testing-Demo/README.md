# k6 Load Testing Demo on AKS

Demonstrates all major k6 load testing patterns using the **k6 Operator** running inside AKS, with results flowing to **Azure Managed Prometheus** and **Azure Managed Grafana**.

## Architecture

```
k6 Runner Pods (k6-tests ns)
        │
        │ --out experimental-prometheus-rw
        ▼
Prometheus Relay (monitoring ns)        ← kube-prometheus-stack
  remote-write-receiver enabled
        │
        │ remote write + workload identity
        ▼
Azure Managed Prometheus
        │
        ▼
Azure Managed Grafana ──── k6 dashboard (ID: 18030)
                     └──── AKS dashboards (built-in)
```

The **go-httpbin** app serves as the target — it exposes `/get`, `/post`, `/delay/{n}`, and `/status/{code}` endpoints without any extra deployment complexity.

## Prerequisites

| Tool | Purpose |
|------|---------|
| `az` (Azure CLI) | Provision Azure resources |
| `kubectl` | Apply Kubernetes manifests |
| `helm` | Install k6 Operator + Prometheus |
| `envsubst` (gettext) | Template the Prometheus values file |

Install `envsubst` on macOS: `brew install gettext && brew link --force gettext`

## Deploy

```bash
# 1. Log in to Azure
az login

# 2. Run the deployment (creates RG, AKS, Managed Prometheus, Grafana, k6 Operator)
chmod +x deploy.sh cleanup.sh k6-operator/install.sh
./deploy.sh
```

The script outputs the Grafana URL and Prometheus query endpoint on completion.

## Run a Test Scenario

```bash
# Apply the scenario (ConfigMap + TestRun)
kubectl apply -f scenarios/01-smoke-test/

# Watch the test run
kubectl get testrun -n k6-tests -w

# Stream runner pod logs
kubectl logs -n k6-tests -l k6_cr=smoke-test -f
```

Delete the `TestRun` between runs to re-apply:
```bash
kubectl delete testrun smoke-test -n k6-tests
kubectl apply -f scenarios/01-smoke-test/
```

## Grafana Setup

1. Open the Grafana URL printed by `deploy.sh`
2. Dashboards → Import → enter ID **18030** → select the Azure Managed Prometheus data source
3. Run any scenario — metrics appear within ~30 seconds

## Scenarios

| # | Name | Pattern | VUs | Purpose |
|---|------|---------|-----|---------|
| 01 | Smoke Test | Fixed 2 VUs, 2 min | 2 | Sanity check before heavier tests |
| 02 | Load Test | Ramp → hold → ramp | 50 | Normal steady-state load |
| 03 | Stress Test | Staircase ramp | 300 (3 pods × 100) | Find capacity ceiling |
| 04 | Spike Test | Two sudden bursts | 500 (2 pods × 250) | Simulate flash-sale traffic |
| 05 | Soak Test | Hold 20 min | 50 | Expose memory leaks |
| 06 | Breakpoint Test | Ramp to 1000, abortOnFail | 1000 | Find exact breaking point |
| 07 | Advanced | Groups, custom metrics, handleSummary | 20 | Full k6 observability API |

### Key concepts demonstrated

- **`stages`** — shape the traffic curve (ramp-up, hold, ramp-down)
- **`thresholds`** — define pass/fail SLOs; `abortOnFail` halts the test automatically
- **`parallelism`** — distribute VUs across multiple k6 runner pods for true distributed load
- **`group()`** — segment requests by logical flow (read path, write path)
- **Custom metrics** — `Counter`, `Rate`, `Trend` tracked alongside built-in metrics
- **`handleSummary()`** — emit structured output at test end (no external dependencies)
- **Tags** — `--tag scenario=<name>` lets you filter results by scenario in Grafana

## Target App Endpoints

| Endpoint | Behaviour |
|----------|-----------|
| `GET /get` | Returns request metadata as JSON |
| `POST /post` | Echoes the request body |
| `GET /delay/1` | Responds after 1 second (simulates slow DB call) |
| `GET /status/500` | Returns 500 (simulates error path) |

Service address from inside the cluster: `http://httpbin.demo-apps.svc.cluster.local`

## HPA Autoscaling

The httpbin deployment ships with an HPA (2–10 replicas, CPU 50%). During stress and spike tests you can watch the app scale out:

```bash
kubectl get hpa httpbin -n demo-apps -w
```

## Cleanup

```bash
./cleanup.sh
```

Deletes the resource group and all Azure resources. This does not remove local kubeconfig entries.
