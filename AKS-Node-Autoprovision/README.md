# AKS Node Autoprovisioning

Automatically provision AKS nodes based on workload requirements without managing node pools manually.

## 📋 Overview

AKS Node Autoprovisioning (NAP) automatically creates nodes with the right specifications based on pending pods' resource requirements. This eliminates the need to manually configure node pools for different workload types.

> **Note**: This is a preview feature and requires feature registration.

## 📁 Contents

```
AKS-Node-Autoprovision/
├── README.md                      # This documentation
├── commands.azcli                 # Azure CLI deployment commands
├── nodepool-auto-provision.yaml   # Node pool configuration
└── sample-deployment.yaml         # Sample deployment for testing
```

## 🚀 Quick Start

### 1. Register the Preview Feature

```bash
# Add/update AKS preview extension
az extension add --name aks-preview
az extension update --name aks-preview

# Register the feature
az feature register --namespace "Microsoft.ContainerService" --name "NodeAutoProvisioningPreview"

# Check registration status
az feature show --namespace "Microsoft.ContainerService" --name "NodeAutoProvisioningPreview"

# Register the provider
az provider register --namespace Microsoft.ContainerService
```

### 2. Create AKS Cluster with Autoprovisioning

```bash
export RESOURCE_GROUP_NAME="aks-node-autoprovision"
export CLUSTER_NAME="aks-node-autoprovision"
export LOCATION="northeurope"

# Create resource group
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

# Create AKS cluster with autoprovisioning
az aks create \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --node-provisioning-mode Auto \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-dataplane cilium \
  --generate-ssh-keys \
  --location $LOCATION
```

### 3. Test Autoprovisioning

```bash
# Apply node pool configuration
kubectl apply -f nodepool-auto-provision.yaml

# Deploy sample workload
kubectl apply -f sample-deployment.yaml
```

## 🔧 Key Features

- **Automatic Node Selection**: Chooses optimal VM sizes based on pod requirements
- **Cost Optimization**: Provisions right-sized nodes to minimize waste
- **Reduced Management**: No manual node pool configuration needed
- **Workload Flexibility**: Handles diverse resource requirements automatically

## 📋 Requirements

- Azure CLI with aks-preview extension
- Registered NodeAutoProvisioningPreview feature
- Network configuration:
  - Azure CNI with overlay mode
  - Cilium dataplane

## 💡 How It Works

1. **Pod Scheduling**: Kubernetes scheduler attempts to place pods
2. **Resource Analysis**: If pods can't be scheduled due to insufficient resources, NAP analyzes their requirements
3. **Node Provisioning**: NAP automatically creates nodes with appropriate specifications
4. **Pod Placement**: Pods are scheduled on newly provisioned nodes

## ⚠️ Considerations

- Preview features may have limitations
- Requires specific network configuration
- Node provisioning takes time (typically 2-5 minutes)
- Consider cost implications of automatic scaling

## 📚 Learn More

- [AKS Node Autoprovisioning Overview](https://learn.microsoft.com/azure/aks/node-autoprovision)
- [Node Pool Management](https://learn.microsoft.com/azure/aks/manage-node-pools)

## 📄 License

This demo is provided for educational purposes.
