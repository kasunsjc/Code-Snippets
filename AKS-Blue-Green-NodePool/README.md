# AKS Blue-Green Node Pool Upgrade (Preview)

Demonstrate the AKS blue-green node pool upgrade preview feature on Azure Kubernetes Service (AKS). This built-in feature automates the blue-green upgrade lifecycle — creating a parallel green pool, draining workloads in batches, providing soak periods for validation, and supporting rollback.

## 📋 Overview

Blue-green node pool upgrades are an **AKS preview feature** that provides a built-in upgrade strategy for node pools. Unlike manual blue-green deployments where you create pools, patch nodeSelectors, and drain nodes yourself, this feature handles the entire process automatically via `az aks nodepool upgrade`.

### How It Works

1. **Cordon blue nodes** — Existing nodes are marked as unschedulable
2. **Create green pool** — A parallel node pool is provisioned with the new configuration
3. **Drain in batches** — Workloads are progressively drained from blue nodes and rescheduled on green nodes, respecting PodDisruptionBudgets
4. **Batch soak** — Pause between drain batches for observation
5. **Final soak** — Validation period before committing (rollback is available during this period)
6. **Commit** — Blue pool is deleted and green becomes the active pool

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **Automated lifecycle** | No manual nodeSelector patching, cordoning, or draining |
| **Batch-based draining** | Configurable batch sizes with soak periods |
| **Built-in rollback** | Rollback to blue pool during the final soak period |
| **PDB-aware** | Respects PodDisruptionBudgets during drain |
| **Pause/abort** | Abort an in-progress upgrade at any time |

## 📁 Contents

```
AKS-Blue-Green-NodePool/
├── README.md                    # This documentation
├── main.bicep                   # Bicep template for AKS cluster with user node pool
├── main.bicepparam              # Bicep parameter file
├── deploy.sh                    # Deployment + blue-green strategy configuration
├── blue-green-upgrade.sh        # Interactive upgrade demo walkthrough
├── sample-deployment.yaml       # Sample workload with PodDisruptionBudget
└── cleanup.sh                   # Resource cleanup script
```

## ⚙️ Prerequisites

- Azure CLI 2.64.0+
- `aks-preview` CLI extension (installed automatically by `deploy.sh`)
- Azure subscription with sufficient quota for doubling node capacity
- `kubectl` installed locally

## 🚀 Quick Start

### Option A: One-Command Deploy

```bash
./deploy.sh
```

This script handles everything:
1. Installs/updates the `aks-preview` CLI extension
2. **Prompts you to select a Kubernetes version** from the available versions in the region
3. Creates a resource group and deploys the AKS cluster via Bicep with the selected version
4. Configures the user node pool with `--upgrade-strategy bluegreen`
5. Sets blue-green properties (batch size, soak durations, drain timeout)
6. Deploys a sample application with a PodDisruptionBudget
7. Verifies the deployment

### Option B: Manual Deploy

```bash
# Install aks-preview extension
az extension add --name aks-preview

# Create resource group
az group create --name aks-bluegreen-demo --location northeurope

# Deploy the Bicep template
az deployment group create \
    --resource-group aks-bluegreen-demo \
    --template-file main.bicep \
    --parameters main.bicepparam

# Configure blue-green upgrade strategy on the node pool
az aks nodepool update \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --name userpool \
    --upgrade-strategy bluegreen \
    --drain-batch-size "50%" \
    --drain-timeout-bg 30 \
    --batch-soak-duration 5 \
    --final-soak-duration 60

# Get cluster credentials
az aks get-credentials --resource-group aks-bluegreen-demo --name aks-bluegreen-cluster

# Deploy sample workload
kubectl create ns demo
kubectl apply -f sample-deployment.yaml -n demo
```

## 🔄 Blue-Green Upgrade Demo

### Run the Interactive Demo

```bash
./blue-green-upgrade.sh
```

The script walks through each step interactively. Below is the manual walkthrough.

### Step 1: Configure Blue-Green Settings

Customize the upgrade behavior on your node pool:

```bash
az aks nodepool update \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --name userpool \
    --upgrade-strategy bluegreen \
    --drain-batch-size "50%" \
    --drain-timeout-bg 30 \
    --batch-soak-duration 5 \
    --final-soak-duration 60
```

### Step 2: Start Blue-Green Upgrade

The `blue-green-upgrade.sh` script **prompts you to select the target version** from the available upgrade paths for your cluster. This ensures you always pick a valid version and avoids version incompatibility errors.

The script automatically handles:
1. Listing available upgrade versions for your cluster
2. Letting you choose the target version (or a node image upgrade)
3. Upgrading the control plane first to the selected version
4. Upgrading the node pool via the blue-green strategy

```bash
# Interactive — lists versions and lets you choose:
./blue-green-upgrade.sh
```

Or manually:

```bash
# Step 2a: Upgrade the control plane to target version first
az aks upgrade \
    --name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --kubernetes-version <target-version> \
    --control-plane-only \
    --yes

# Step 2b: Then upgrade the node pool using blue-green strategy
az aks nodepool upgrade \
    --name userpool \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --kubernetes-version <target-version>
```

Or perform a node image upgrade:

```bash
az aks nodepool upgrade \
    --name userpool \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --node-image-only
```

You can also start a blue-green upgrade on a node pool not yet configured with the strategy:

```bash
az aks nodepool upgrade \
    --name userpool \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo \
    --kubernetes-version <target-version> \
    --upgrade-strategy bluegreen
```

### Step 3: Monitor Progress

```bash
# Check provisioning state
az aks nodepool show \
    -g aks-bluegreen-demo \
    --cluster-name aks-bluegreen-cluster \
    -n userpool \
    --query provisioningState -o tsv

# Watch nodes (blue and green will both be visible during upgrade)
watch -n 10 kubectl get nodes -o wide

# Watch pod migrations
watch -n 10 kubectl get pods -n demo -o wide
```

### Step 4: Pause/Abort (if needed)

```bash
az aks nodepool operation-abort \
    --name userpool \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo
```

### Step 5: Rollback (during final soak period only)

```bash
az aks nodepool rollback \
    --name userpool \
    --cluster-name aks-bluegreen-cluster \
    --resource-group aks-bluegreen-demo
```

> ⚠️ Rollback is **only available during the final soak period**. Once the soak expires and the blue pool is deleted, rollback is no longer possible.

## ⚙️ Blue-Green Upgrade Properties

| Property | CLI Flag | Description | Default |
|----------|----------|-------------|---------|
| `drainBatchSize` | `--drain-batch-size` | Nodes to drain per batch (integer or percentage) | 10% |
| `drainTimeoutInMinutes` | `--drain-timeout-bg` | Max time to wait for pod termination per node | 30 min |
| `batchSoakDurationInMinutes` | `--batch-soak-duration` | Pause between drain batches | 15 min |
| `finalSoakDurationInMinutes` | `--final-soak-duration` | Validation period after all nodes drained | 60 min |

## 🔄 Supported Upgrade Scenarios

| Scenario | Command |
|----------|---------|
| **Kubernetes version** | `--kubernetes-version 1.31` |
| **Node image only** | `--node-image-only` |
| **Auto-upgrade channels** | Works with configured auto-upgrade channels |
| **Planned maintenance** | Compatible with maintenance windows |

## ⚠️ Limitations and Considerations

- **Preview feature** — Requires `aks-preview` CLI extension
- **Control plane first** — For Kubernetes version upgrades, the control plane must be upgraded to the target version before the node pool (node pool version cannot exceed control plane version)
- **Double capacity** — Requires temporarily doubling node pool capacity (increased cost)
- **No automated rollback** — Rollback must be manually initiated during the final soak period
- **No VM pools** — Not supported with virtual machine node pools
- **No maxUnavailable** — The `maxUnavailable` setting doesn't apply to blue-green upgrades
- **Stateful workloads** — Plan carefully for data consistency during migration
- **API version** — Requires API version `2025-08-02-preview` or later

## 📋 Requirements

- Azure CLI 2.64.0+
- `aks-preview` Azure CLI extension
- Azure subscription with quota for doubling node capacity
- `kubectl` installed locally

## 🧹 Cleanup

```bash
./cleanup.sh
```

This aborts any active upgrades, removes the kubectl context, and deletes the resource group. Or manually:

```bash
az group delete --name aks-bluegreen-demo --yes --no-wait
```

## 📚 Learn More

- [Blue-Green Node Pool Upgrades (Preview)](https://learn.microsoft.com/en-us/azure/aks/blue-green-node-pool-upgrade)
- [Manual Blue-Green Node Pool Upgrades](https://learn.microsoft.com/en-us/azure/aks/how-does-upgrade-happen#blue-green-node-pool-upgrades-manual)
- [Upgrade AKS Node Pools](https://learn.microsoft.com/en-us/azure/aks/node-image-upgrade)
- [Roll Back Node Pool Versions](https://learn.microsoft.com/en-us/azure/aks/roll-back-node-pool-version)
- [AKS Auto-Upgrade Channels](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster)

## 📄 License

This demo is provided for educational purposes.
