# k6 Load Testing Demo on AKS

This demo shows practical k6 patterns on AKS using the k6 Operator and a sample target app. It is intentionally simple: no Prometheus, no Grafana, and no metrics relay.

## Architecture

```
k6 TestRun CRDs (k6-tests namespace)
        |
        v
k6 Runner Pods
        |
        v
go-httpbin app (demo-apps namespace)
        |
        v
Results in runner pod logs
```

## What Gets Deployed

- AKS cluster (Standard tier)
- k6 Operator (Helm)
- go-httpbin sample app + HPA
- 7 scenario folders (ConfigMap + TestRun per scenario)

## Prerequisites

| Tool | Purpose |
|------|---------|
| `az` | Provision Azure resources |
| `kubectl` | Apply Kubernetes manifests |
| `helm` | Install k6 Operator |

## Quick Start

```bash
# 1. Authenticate
az login

# 2. Deploy infra + operator + sample app
chmod +x deploy.sh cleanup.sh k6-operator/install.sh
./deploy.sh
```

## Run a Scenario

```bash
# Apply ConfigMap + TestRun
kubectl apply -f scenarios/01-smoke-test/

# Watch TestRun state
kubectl get testrun -n k6-tests -w

# Stream runner output
kubectl logs -n k6-tests -l k6_cr=smoke-test -f
```

Run the same scenario again:

```bash
kubectl delete testrun smoke-test -n k6-tests
kubectl apply -f scenarios/01-smoke-test/
```

## Scenario Catalog

| # | Name | Pattern | Parallelism | Goal |
|---|------|---------|-------------|------|
| 01 | Smoke Test | Fixed 2 VUs | 1 | Sanity check |
| 02 | Load Test | Ramp-hold-ramp | 1 | Baseline steady traffic |
| 03 | Stress Test | Staircase ramp | 3 | Find scaling limits |
| 04 | Spike Test | Sudden bursts | 2 | Simulate traffic spikes |
| 05 | Soak Test | Long hold | 1 | Find long-run instability |
| 06 | Breakpoint Test | Ramp + abortOnFail | 1 | Identify break threshold |
| 07 | Advanced | groups + custom metrics + summary | 1 | Advanced k6 scripting patterns |

## Useful Commands

```bash
# List all scenarios
find scenarios -maxdepth 1 -mindepth 1 -type d | sort

# List k6 pods
kubectl get pods -n k6-tests

# Watch target app autoscaling
kubectl get hpa httpbin -n demo-apps -w

# Delete all TestRun objects
kubectl delete testrun --all -n k6-tests
```

## Target App Endpoints

| Endpoint | Behavior |
|----------|----------|
| `GET /get` | Returns request metadata |
| `POST /post` | Echoes request body |
| `GET /delay/1` | Responds after 1 second |
| `GET /status/500` | Returns 500 |

Internal URL used by scenarios:

`http://httpbin.demo-apps.svc.cluster.local`

## Cleanup

```bash
./cleanup.sh
```

Deletes the demo resource group and all contained Azure resources.
