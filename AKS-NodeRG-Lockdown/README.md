# AKS Node Resource Group Lockdown

Enhance AKS security by restricting access to node resource group resources.

## 📋 Overview

AKS Node Resource Group (NRG) Lockdown prevents unauthorized modifications to resources in the managed node resource group. This feature adds an extra layer of security by making the node resource group read-only.

> **Note**: This is a preview feature and requires feature registration.

## 📁 Contents

```
AKS-NodeRG-Lockdown/
├── README.md       # This documentation
└── commands.sh     # Deployment and configuration commands
```

## 🚀 Quick Start

### Run the Demo

```bash
./commands.sh
```

This script will:
1. Register the preview feature (if not already registered)
2. Create a resource group
3. Deploy an AKS cluster **without** lockdown (baseline)
4. Deploy an AKS cluster **with** lockdown (ReadOnly restriction)

## 🔧 Feature Registration

```bash
# Add/update AKS preview extension
az extension add --name aks-preview
az extension update --name aks-preview

# Register the feature
az feature register --namespace "Microsoft.ContainerService" --name "NRGLockdownPreview"

# Wait for registration (can take several minutes)
az feature show --namespace "Microsoft.ContainerService" --name "NRGLockdownPreview"

# Register the provider
az provider register --namespace Microsoft.ContainerService
```

## 💻 Create Cluster with NRG Lockdown

```bash
az aks create \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --location $LOCATION \
  --nrg-lockdown-restriction-level ReadOnly \
  --generate-ssh-keys
```

## 🔐 Restriction Levels

| Level | Description |
|-------|-------------|
| **ReadOnly** | Prevents any modifications to node resource group resources |
| **Unrestricted** | Default behavior, no additional restrictions |

## 🎯 Benefits

- **Security Compliance**: Prevents accidental or malicious modifications to cluster infrastructure
- **Audit Trail**: All attempts to modify restricted resources are logged
- **Governance**: Enforces infrastructure-as-code practices
- **Protection**: Guards against human errors that could destabilize the cluster

## ⚠️ Considerations

- **Preview Feature**: May have limitations or changes
- **Operational Impact**: Some management operations may require adjustments
- **Emergency Access**: Plan for scenarios requiring infrastructure modifications
- **Existing Clusters**: Feature applies to new clusters; existing clusters need migration

## 💡 Use Cases

1. **Production Environments**: Protect critical infrastructure from unauthorized changes
2. **Compliance Requirements**: Meet regulatory requirements for infrastructure protection
3. **Multi-Team Scenarios**: Prevent cross-team modifications to shared infrastructure
4. **Audit Requirements**: Ensure all changes go through proper CI/CD pipelines

## 📊 Comparing Clusters

After running the demo script, you'll have two clusters:
- `aks-nrg` - Standard cluster (baseline)
- `aks-nrg-lockdown` - Cluster with NRG lockdown

Try modifying resources in both node resource groups to see the difference:

```bash
# List node resource groups
az group list --query "[?contains(name, 'MC_')].name" -o tsv

# Attempt to create a resource in the locked-down group
# This should fail with access denied
az storage account create \
  --name testaccount$RANDOM \
  --resource-group <locked-node-rg-name> \
  --location $LOCATION
```

## 📚 Learn More

- [AKS Node Resource Group Lockdown](https://learn.microsoft.com/azure/aks/cluster-configuration#node-resource-group-lockdown)
- [AKS Security Best Practices](https://learn.microsoft.com/azure/aks/operator-best-practices-cluster-security)

## 📄 License

This demo is provided for educational purposes.
