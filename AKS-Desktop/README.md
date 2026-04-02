# AKS Automatic Cluster with Azure Managed Prometheus & Grafana

This deploys an **AKS Automatic** cluster with full observability using **Azure Managed Prometheus** and **Azure Managed Grafana**.

## What Gets Deployed

| Resource | Description |
|----------|-------------|
| AKS Automatic Cluster | Managed Kubernetes with Automatic SKU (node autoprovision, KEDA, VPA built-in) |
| Azure Monitor Workspace (Prometheus) | Managed Prometheus for metrics collection |
| Azure Managed Grafana | Dashboards integrated with Prometheus |
| Log Analytics Workspace | Container Insights log collection |
| Data Collection Rule & Endpoint | Prometheus metrics forwarding pipeline |
| Prometheus Recording Rule Groups | Node and Kubernetes recording rules |
| Role Assignments | Grafana → Prometheus reader roles, user Grafana Admin |

## Prerequisites

- Azure CLI installed
- An active Azure subscription
- Logged in via `az login`

## Deployment

1. Update `main.bicepparam` with your desired values (or use the deploy script which auto-detects your user ID):

```bash
chmod +x deploy.sh
./deploy.sh
```

2. Or deploy manually:

```bash
az group create --name rg-aks-automatic --location eastus

az deployment group create \
  --resource-group rg-aks-automatic \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## Access

```bash
# Get AKS credentials
az aks get-credentials --resource-group rg-aks-automatic --name aks-automatic

# Verify nodes
kubectl get nodes

# Get Grafana URL from deployment outputs
az deployment group show \
  --resource-group rg-aks-automatic \
  --name aks-automatic-deployment \
  --query 'properties.outputs.grafanaEndpoint.value' -o tsv
```

## Deploy Sample App

```bash
kubectl apply -f sample-app.yaml
```

## Load Test

```bash
k6 run load-test.js
```

## Cleanup

```bash
az group delete --name rg-aks-automatic --yes --no-wait
```
