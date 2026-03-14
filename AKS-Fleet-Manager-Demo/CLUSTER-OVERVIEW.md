# AKS Fleet Manager Demo - Cluster Overview

## Cluster Configuration

This demo deploys **6 AKS clusters** organised by environment:

| Cluster Name | Environment | Location | K8s Version | Fleet Status | Purpose |
|--------------|-------------|----------|-------------|--------------|---------|
| aks-dev-1-demo | Dev | westeurope | 1.33.5 | ✅ Connected | Dev fleet member |
| **aks-dev-2-demo** | Dev | northeurope | 1.33.5 | ⚠️ **Standalone** | **Demo: Connect to Fleet** |
| aks-acc-1-demo | ACC | westeurope | 1.33.5 | ✅ Connected | ACC fleet member |
| aks-acc-2-demo | ACC | northeurope | 1.33.5 | ✅ Connected | ACC fleet member |
| aks-prod-1-demo | Prod | westeurope | 1.32 | ✅ Connected | Prod fleet member |
| aks-prod-2-demo | Prod | northeurope | 1.32 | ✅ Connected | Prod fleet member |

## Fleet Membership

### Connected Clusters (5)
These clusters are **automatically connected** to the fleet during initial deployment:
- `aks-dev-1-demo-member` (Dev)
- `aks-acc-1-demo-member` (ACC)
- `aks-acc-2-demo-member` (ACC)
- `aks-prod-1-demo-member` (Prod)
- `aks-prod-2-demo-member` (Prod)

### Standalone Cluster (1)
**Dev Cluster 2 is intentionally NOT connected** to demonstrate the fleet connection process:
- `aks-dev-2-demo` - Deployed but not joined to fleet

## Why Dev-2 is Standalone

In production environments, you often have **existing AKS clusters** that need to be gradually onboarded to a Fleet Manager. The dev-2 cluster simulates this real-world scenario by:

1. ✅ Being a fully functional AKS cluster
2. ✅ Deployed with the same networking and monitoring
3. ⚠️ **NOT** connected to the fleet initially
4. 💡 Ready to be used in a **live demo** of the connection process

## How to Connect Dev-2

### Option 1: Automated (Recommended for Demos)
```bash
./connect-cluster.sh rg-aks-fleet-demo-01
```

### Option 2: Manual (Step-by-Step Learning)
```bash
# Get Fleet Manager name
FLEET_NAME=$(az fleet list --resource-group rg-aks-fleet-demo-01 --query "[0].name" -o tsv)

# Get cluster resource ID
CLUSTER_ID=$(az aks show \
  --name aks-dev-2-demo \
  --resource-group rg-aks-fleet-demo-01 \
  --query id -o tsv)

# Create fleet membership
az fleet member create \
  --fleet-name $FLEET_NAME \
  --resource-group rg-aks-fleet-demo-01 \
  --name aks-dev-2-demo-member \
  --member-cluster-id $CLUSTER_ID

# Verify
kubectl get memberclusters
```

## Verification Commands

### Check Fleet Status
```bash
# List all fleet members
az fleet member list \
  --fleet-name <fleet-name> \
  --resource-group rg-aks-fleet-demo-01 \
  --output table

# Should show 5 members initially, 6 after connecting dev-2
```

### Check from Fleet Hub
```bash
# Get fleet credentials
az fleet get-credentials \
  --resource-group rg-aks-fleet-demo-01 \
  --name <fleet-name>

# View member clusters
kubectl get memberclusters

# Check resource propagation
kubectl get clusterresourceplacement
```

### Test Resource Propagation to Dev-2
After connecting dev-2, verify that existing workloads propagate:

```bash
# Check if fleet-demo namespace exists
kubectl get namespace fleet-demo --context aks-dev-2-demo

# Check if pods are running
kubectl get pods -n fleet-demo --context aks-dev-2-demo

# If PickAll placements exist, they should automatically include dev-2
kubectl describe clusterresourceplacement demo-app-placement
```

## Network Configuration

All clusters share the following network setup:

### Clusters in West Europe (using vnet1)
- aks-dev-1-demo (Dev)
- aks-acc-1-demo (ACC)
- aks-prod-1-demo (Prod)
- **Subnet:** 10.1.0.0/22

### Clusters in North Europe (using vnet2)
- **aks-dev-2-demo** ⚠️ (Dev - standalone)
- aks-acc-2-demo (ACC)
- aks-prod-2-demo (Prod)
- **Subnet:** 10.2.0.0/22

## Demo Scenarios Using Dev-2

### Scenario: Dynamic Fleet Expansion
1. Show existing fleet with 5 members across dev/acc/prod
2. Demonstrate standalone dev-2 cluster exists but is isolated
3. Connect dev-2 to fleet using `connect-cluster.sh`
4. Show that existing ClusterResourcePlacements automatically propagate
5. Verify workloads are running on dev-2

### Scenario: Gradual Onboarding
1. Deploy a new application using PickAll placement (only goes to 5 clusters)
2. Connect dev-2
3. Show the application automatically deploys to dev-2
4. Demonstrate fleet's self-healing and reconciliation

### Scenario: Selective Rollout
1. Label dev-2 with `newcluster=true`
2. Create ClusterResourcePlacement targeting only new clusters
3. Deploy test workloads only to dev-2
4. Validate before expanding to other clusters

## Resource Tags

Dev-2 has special tags to identify it as a standalone cluster:

```yaml
tags:
  Environment: 'dev'
  Project: 'AKS-Fleet-Manager'
  ManagedBy: 'Bicep'
  Cluster: 'dev-2-standalone'
  Region: 'northeurope'
  Standalone: 'true'
```

This makes it easy to identify in Azure Portal or via Azure Resource Graph queries.

## Troubleshooting

### Dev-2 Not Deploying
If dev-2 doesn't deploy during `./deploy.sh`:
- Check Azure subscription quota for AKS clusters
- Verify vnet2 deployed successfully
- Check deployment logs in Azure Portal

### Connection Fails
If connecting dev-2 fails:
```bash
# Verify cluster exists
az aks show --name aks-dev-2-demo --resource-group rg-aks-fleet-demo-01

# Check Fleet Manager exists
az fleet show --name <fleet-name> --resource-group rg-aks-fleet-demo-01

# Verify RBAC permissions
az role assignment list --scope <cluster-resource-id>
```

### Resources Don't Propagate
After connecting dev-2, if resources don't appear:
```bash
# Check placement status
kubectl describe clusterresourceplacement <placement-name>

# Verify cluster is healthy
kubectl get membercluster aks-dev-2-demo

# Check if cluster matches placement selector
kubectl get membercluster aks-dev-2-demo -o yaml
```

## Summary

✅ **5 clusters** automatically connected to fleet (1 Dev + 2 ACC + 2 Prod)  
⚠️ **1 cluster** (dev-2) standalone for connection demo  
📚 **connect-cluster.sh** script for easy demonstration  
🎯 **Real-world scenario** simulating gradual fleet adoption  
💡 **Learning opportunity** to understand fleet membership process
