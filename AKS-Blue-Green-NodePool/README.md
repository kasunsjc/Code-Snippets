# AKS Blue-Green Node Pool Deployment

Demonstrate the blue-green node pool upgrade strategy for Azure Kubernetes Service (AKS). This approach enables zero-downtime upgrades by creating a new node pool, migrating workloads, and removing the old pool.

## 📋 Overview

Blue-green deployment at the node pool level lets you upgrade AKS node pools without disrupting running workloads. Instead of performing in-place upgrades, you provision a new ("green") node pool alongside the existing ("blue") pool, migrate your workloads, and then decommission the old pool.

### Why Blue-Green Node Pool Upgrades?

| Benefit | Description |
|---------|-------------|
| **Zero downtime** | Workloads continue running on blue while green is provisioned |
| **Easy rollback** | If something goes wrong, keep blue and remove green |
| **Controlled migration** | Move workloads at your own pace with nodeSelector |
| **Version flexibility** | Upgrade Kubernetes version, VM SKU, or OS SKU per pool |

## 📁 Contents

```
AKS-Blue-Green-NodePool/
├── README.md                    # This documentation
├── main.bicep                   # Bicep template for AKS cluster with blue node pool
├── main.bicepparam              # Bicep parameter file
├── deploy.sh                    # One-command deployment script
├── blue-green-upgrade.sh        # Interactive blue-green upgrade walkthrough
├── sample-deployment.yaml       # Sample workload with nodeSelector
└── cleanup.sh                   # Resource cleanup script
```

## 🚀 Quick Start

### Option A: One-Command Deploy

```bash
./deploy.sh
```

This script handles everything: prerequisite checks, resource group creation, Bicep deployment, credential setup, sample app deployment, and verification.

### Option B: Manual Deploy

```bash
# Create resource group
az group create --name aks-bluegreen-demo --location northeurope

# Deploy the Bicep template
az deployment group create \
    --resource-group aks-bluegreen-demo \
    --template-file main.bicep \
    --parameters main.bicepparam

# Get cluster credentials
az aks get-credentials --resource-group aks-bluegreen-demo --name aks-bluegreen-cluster

# Deploy sample workload
kubectl create ns demo
kubectl apply -f sample-deployment.yaml -n demo
```

## 🔄 Blue-Green Upgrade Walkthrough

### Run the Interactive Demo

```bash
./blue-green-upgrade.sh
```

The script walks you through each step interactively. Below is the manual walkthrough.

### Step 0: Verify Current State

```bash
# View node pools
az aks nodepool list \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --output table

# Nodes with labels
kubectl get nodes -L environment

# Pods running on blue nodes
kubectl get pods -n demo -o wide
```

### Step 1: Create the Green Node Pool

Create a new node pool with updated configuration (e.g., new Kubernetes version, VM SKU, or OS):

```bash
az aks nodepool add \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --name green \
    --node-count 3 \
    --node-vm-size Standard_D2s_v4 \
    --os-sku AzureLinux \
    --labels environment=green \
    --mode User
```

Verify both pools exist:

```bash
az aks nodepool list \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --output table
```

### Step 2: Migrate Workloads to Green

Update the deployment's `nodeSelector` to target the green pool:

```bash
kubectl patch deployment sample-app -n demo --type='json' \
    -p='[{"op": "replace", "path": "/spec/template/spec/nodeSelector/environment", "value": "green"}]'
```

Wait for the rollout and verify pods moved:

```bash
kubectl rollout status deployment/sample-app -n demo
kubectl get pods -n demo -o wide
```

### Step 3: Cordon and Drain Blue Nodes

Prevent new scheduling and evict remaining pods from the blue pool:

```bash
# Cordon blue nodes
BLUE_NODES=$(kubectl get nodes -l environment=blue -o jsonpath='{.items[*].metadata.name}')
for node in $BLUE_NODES; do
    kubectl cordon "$node"
done

# Drain blue nodes
for node in $BLUE_NODES; do
    kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force
done
```

### Step 4: Delete Blue Node Pool

After confirming all workloads have migrated successfully:

```bash
az aks nodepool delete \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --name blue
```

### Step 5: Verify Final State

```bash
# Only green and system pools remain
az aks nodepool list \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --output table

# All workloads on green nodes
kubectl get pods -n demo -o wide
```

## 🔁 Next Upgrade Cycle

For the next upgrade, repeat the process with reversed roles:

1. Create a new **blue** pool with updated configuration
2. Migrate workloads from **green** to **blue**
3. Cordon, drain, and delete the **green** pool

This creates a continuous cycle of blue ↔ green upgrades.

## ⚡ Upgrade Scenarios

| Scenario | Green Pool Configuration |
|----------|-------------------------|
| **Kubernetes version upgrade** | `--kubernetes-version 1.31` |
| **VM SKU change** | `--node-vm-size Standard_D4s_v4` |
| **OS SKU change** | `--os-sku AzureLinux` |
| **Node image update** | New pool automatically gets latest image |
| **Scale change** | `--node-count 5 --enable-cluster-autoscaler --min-count 3 --max-count 10` |

## ⚠️ Important Considerations

- **System node pool** is not part of the blue-green rotation — it handles system pods
- **DaemonSets** run on all nodes automatically and don't need manual migration
- **PersistentVolumes** with `ReadWriteOnce` access mode may need special handling when migrating across zones
- **Pod Disruption Budgets** should be configured to ensure smooth draining
- **Cluster Autoscaler** can be enabled on both pools during migration to handle load spikes
- Ensure the green pool has enough capacity before migrating workloads
- Test the green pool with a canary deployment before full migration

## 📋 Requirements

- Azure CLI 2.61.0+
- Azure subscription with permissions to create AKS clusters
- `kubectl` installed locally

## 🧹 Cleanup

```bash
./cleanup.sh
```

This removes the kubectl context and deletes the resource group with all resources. Or manually:

```bash
az group delete --name aks-bluegreen-demo --yes --no-wait
```

## 📚 Learn More

- [Blue-Green Node Pool Upgrade](https://learn.microsoft.com/en-us/azure/aks/blue-green-node-pool-upgrade)
- [Upgrade AKS Node Pools](https://learn.microsoft.com/en-us/azure/aks/node-image-upgrade)
- [AKS Node Pool Overview](https://learn.microsoft.com/en-us/azure/aks/create-node-pools)
- [Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)

## 📄 License

This demo is provided for educational purposes.
