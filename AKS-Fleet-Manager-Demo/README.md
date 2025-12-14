# AKS Fleet Manager Demo

A comprehensive demonstration of Azure Kubernetes Service (AKS) Fleet Manager capabilities, showcasing multi-cluster orchestration, resource propagation, and centralized management.

## 📋 Overview

This demo deploys an AKS Fleet Manager with two member clusters across different Azure regions, demonstrating key fleet management capabilities including:

- **Multi-cluster orchestration**: Manage multiple AKS clusters as a single fleet
- **Resource propagation**: Deploy applications across multiple clusters from a single point
- **Cluster resource placement**: Control where resources are deployed using sophisticated placement policies
- **Multi-cluster services**: Enable service discovery across member clusters
- **Update management**: Coordinate Kubernetes upgrades across all fleet members
- **Resource overrides**: Customize resource configurations per cluster

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│             AKS Fleet Manager (Hub)                 │
│                                                     │
│  ┌───────────────────────────────────────────┐    │
│  │  ClusterResourcePlacement Controller       │    │
│  │  Multi-cluster Service Discovery          │    │
│  │  Update Orchestration                     │    │
│  └───────────────────────────────────────────┘    │
└────────────┬──────────────┬─────────────────────────┘
             │              │
     ┌───────┴──────┐  ┌────┴───────┐
     │              │  │            │
┌────▼─────────┐   │  │  ┌─────────▼────┐
│ Member       │   │  │  │  Member      │
│ Cluster 1    │   │  │  │  Cluster 2   │
│ (East US)    │   │  │  │  (West US)   │
│              │   │  │  │              │
│ - Workloads  │   │  │  │ - Workloads  │
│ - Services   │   │  │  │ - Services   │
│ - Networking │   │  │  │ - Networking │
└──────────────┘   │  │  └──────────────┘
                   │  │
                   └──┘
           Fleet Membership
```

## 📁 Project Structure

```
AKS-Fleet-Manager-Demo/
├── main.bicep                    # Main infrastructure template
├── main.bicepparam               # Deployment parameters
├── deploy.sh                     # Infrastructure deployment script
├── deploy-samples.sh             # Sample applications deployment
├── cleanup.sh                    # Resource cleanup script
├── commands.sh                   # Useful commands reference
├── README.md                     # This file
├── modules/                      # Bicep modules
│   ├── fleet-manager.bicep      # Fleet Manager resource
│   ├── fleet-member.bicep       # Fleet membership configuration
│   ├── aks-member.bicep         # AKS member cluster
│   ├── vnet.bicep               # Virtual network
│   └── log-analytics.bicep      # Monitoring workspace
└── kubernetes-manifests/         # K8s sample manifests
    ├── 00-cluster-resource-placement.yaml
    ├── 01-namespace.yaml
    ├── 02-nginx-deployment.yaml
    ├── 03-pickn-placement.yaml
    ├── 04-resource-override.yaml
    └── 05-multi-cluster-service.yaml
```

## 🚀 Prerequisites

Before running this demo, ensure you have:

1. **Azure CLI** (version 2.50.0 or later)
   ```bash
   az --version
   ```

2. **kubectl** (version 1.28 or later)
   ```bash
   kubectl version --client
   ```

3. **Azure Subscription** with sufficient permissions to create:
   - AKS Fleet Manager
   - AKS clusters
   - Virtual networks
   - Log Analytics workspace

4. **Resource Providers** registered:
   ```bash
   az provider register --namespace Microsoft.ContainerService
   az provider register --namespace Microsoft.Network
   az provider register --namespace Microsoft.OperationalInsights
   ```

## 🎯 Quick Start

### 1. Clone and Navigate
```bash
cd AKS-Fleet-Manager-Demo
```

### 2. Review Configuration
Edit [main.bicepparam](main.bicepparam) to customize:
- Azure regions for deployment
- Environment name
- Resource tags

### 3. Deploy Infrastructure
```bash
./deploy.sh
```

This script will:
- Create a resource group
- Deploy Fleet Manager with hub cluster
- Deploy two member AKS clusters in different regions
- Configure networking and monitoring
- Register clusters with the fleet
- Configure kubectl contexts

**Expected time:** 15-20 minutes

### 4. Assign RBAC Permissions
After deployment, assign the Fleet Manager admin role to access the hub cluster:

```bash
./assign-fleet-rbac.sh
```

This assigns the **Azure Kubernetes Fleet Manager RBAC Cluster Admin** role to your user account.

**Alternative: Assign during deployment**
```bash
# Get your Object ID
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Deploy with RBAC
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters principalId=$USER_OBJECT_ID
```

### 5. Deploy Sample Applications
```bash
./deploy-samples.sh
```

This deploys:
- Demo namespace propagated to all clusters
- NGINX application with PickAll placement
- Redis application with PickN placement
- Multi-cluster service example

### 5. Verify Deployment

Switch to fleet hub context:
```bash
kubectl config use-context fleet-hub
```

Check member clusters:
```bash
kubectl get memberclusters
```

View resource placements:
```bash
kubectl get clusterresourceplacement
```

Check resources in member clusters:
```bash
# Member Cluster 1
kubectl get pods -n fleet-demo --context aks-member1-demo

# Member Cluster 2
kubectl get pods -n fleet-demo --context aks-member2-demo
```

## 🎓 Demo Scenarios

### Scenario 1: Resource Propagation (PickAll)

Demonstrates deploying resources to all member clusters.

```bash
# Apply from fleet hub
kubectl config use-context fleet-hub
kubectl apply -f kubernetes-manifests/01-namespace.yaml
kubectl apply -f kubernetes-manifests/02-nginx-deployment.yaml
kubectl apply -f kubernetes-manifests/00-cluster-resource-placement.yaml

# Verify propagation
kubectl get clusterresourceplacement demo-app-placement
kubectl describe clusterresourceplacement demo-app-placement

# Check on member clusters
kubectl get pods -n fleet-demo --context aks-member1-demo
kubectl get pods -n fleet-demo --context aks-member2-demo
```

**Key Learning:** Resources defined once on the hub are automatically propagated to all matching member clusters.

### Scenario 2: Selective Placement (PickN)

Demonstrates deploying resources to a specific number of clusters.

```bash
# Apply PickN placement
kubectl apply -f kubernetes-manifests/03-pickn-placement.yaml

# Check which cluster was selected
kubectl describe clusterresourceplacement pickn-demo-placement
```

**Key Learning:** Fleet Manager can intelligently select optimal clusters based on capacity and health.

### Scenario 3: Resource Override

Demonstrates customizing resource configurations per cluster.

```bash
# Label clusters
kubectl label membercluster <member1-name> environment=production
kubectl label membercluster <member2-name> environment=development

# Apply override
kubectl apply -f kubernetes-manifests/04-resource-override.yaml

# Verify different replica counts
kubectl get deployment nginx-demo -n fleet-demo --context aks-member1-demo
kubectl get deployment nginx-demo -n fleet-demo --context aks-member2-demo
```

**Key Learning:** Override policies allow customization while maintaining centralized management.

### Scenario 4: Multi-Cluster Services

Demonstrates service discovery across clusters.

```bash
# Deploy multi-cluster service
kubectl apply -f kubernetes-manifests/05-multi-cluster-service.yaml

# Check ServiceExport
kubectl get serviceexport -n multi-cluster-svc

# Verify service in member clusters
kubectl get svc backend-service -n multi-cluster-svc --context aks-member1-demo
kubectl get svc backend-service -n multi-cluster-svc --context aks-member2-demo
```

**Key Learning:** Services can be discovered and consumed across cluster boundaries.

## 🔍 Key Concepts

### ClusterResourcePlacement (CRP)

Controls how resources are distributed across member clusters:

- **PickAll**: Deploy to all matching clusters
- **PickN**: Deploy to N specific clusters
- **PickFixed**: Deploy to explicitly named clusters

### Placement Policies

Fine-grained control over resource placement:

```yaml
policy:
  placementType: PickAll
  affinity:
    clusterAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        clusterSelectorTerms:
          - labelSelector:
              matchLabels:
                region: eastus
```

### Resource Overrides

Customize resources per cluster without duplicating manifests:

```yaml
overrideRules:
  - clusterSelector:
      clusterSelectorTerms:
        - labelSelector:
            matchLabels:
              environment: production
    jsonPatchOverrides:
      - op: replace
        path: /spec/replicas
        value: 5
```

## 📊 Monitoring and Observability

### View Fleet Status
```bash
# Fleet hub components
kubectl get all -n fleet-system

# Placement status
kubectl get clusterresourceplacement -o wide

# Member cluster health
kubectl get membercluster -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].status
```

### Azure Monitor Integration

All clusters are integrated with Azure Monitor:

```bash
# Query logs via Azure CLI
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "KubePodInventory | where Namespace == 'fleet-demo'"
```

## 🛠️ Troubleshooting

### RBAC Access Denied

**Error:** `User does not have access to the resource in Azure. Update role assignment to allow access.`

**Solution:**
```bash
# Run the RBAC assignment script
./assign-fleet-rbac.sh

# Or assign manually
az role assignment create \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "18ab4d3d-a1bf-4477-8ad9-8359bc988f69" \
  --scope $(az fleet show --resource-group rg-aks-fleet-demo --name <fleet-name> --query id -o tsv)
```

### Resources Not Propagating

1. Check CRP status:
   ```bash
   kubectl describe clusterresourceplacement <name>
   ```

2. Verify member cluster health:
   ```bash
   kubectl get membercluster
   ```

3. Check fleet-system logs:
   ```bash
   kubectl logs -n fleet-system deployment/fleet-controller-manager -f
   ```

### Member Cluster Not Joining

1. Verify cluster is running:
   ```bash
   az aks show --resource-group rg-aks-fleet-demo --name <cluster-name>
   ```

2. Check fleet membership:
   ```bash
   az fleet member list --fleet-name <fleet-name> --resource-group rg-aks-fleet-demo
   ```

### Context Issues

Reset kubectl contexts:
```bash
# Re-get credentials
az fleet get-credentials --resource-group rg-aks-fleet-demo --name <fleet-name>
az aks get-credentials --resource-group rg-aks-fleet-demo --name <cluster-name>

# List contexts
kubectl config get-contexts
```

## 🧹 Cleanup

To remove all resources:

```bash
./cleanup.sh
```

This will:
- Delete the resource group (Fleet Manager + all member clusters)
- Remove virtual networks and associated resources
- Clean up kubectl contexts

**Note:** Resource deletion is initiated in the background and may take several minutes to complete.

## 📚 Additional Resources

- [AKS Fleet Manager Documentation](https://learn.microsoft.com/azure/kubernetes-fleet/)
- [Kubernetes Fleet API](https://github.com/Azure/fleet)
- [Multi-Cluster Services](https://learn.microsoft.com/azure/kubernetes-fleet/concepts-multicluster-service)
- [Update Orchestration](https://learn.microsoft.com/azure/kubernetes-fleet/update-orchestration)

## 💡 Use Cases

1. **Multi-Region Deployments**: Deploy applications across geographic regions for high availability
2. **Environment Management**: Separate dev, staging, and production clusters with centralized control
3. **Compliance and Governance**: Enforce policies across all clusters from a single point
4. **Disaster Recovery**: Maintain synchronized workloads across regions for failover scenarios
5. **Cost Optimization**: Intelligently distribute workloads based on cluster capacity and cost

## 🤝 Contributing

Feel free to submit issues or pull requests to improve this demo.

## 📄 License

This demo is provided as-is for educational purposes.

---

**Created:** December 2025  
**Maintained by:** Cloud Architecture Team
