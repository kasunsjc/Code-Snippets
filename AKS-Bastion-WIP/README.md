# AKS Private Cluster with Azure Bastion Demo

This demo showcases how to securely connect to an Azure Kubernetes Service (AKS) private cluster using Azure Bastion's **native client tunneling feature**. No jump box VM needed! The infrastructure is deployed using Bicep templates and leverages Bastion's preview feature to tunnel directly to the AKS API server.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [What Gets Deployed](#what-gets-deployed)
- [Deployment Steps](#deployment-steps)
- [Connecting to the AKS Cluster](#connecting-to-the-aks-cluster)
- [Testing the Setup](#testing-the-setup)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [Cost Considerations](#cost-considerations)

## 🎯 Overview

This demo demonstrates the modern way to manage private AKS clusters using:

- **Private AKS Cluster**: API server is not exposed to the public internet
- **Azure Bastion with Native Client Tunneling**: Direct tunnel to AKS without needing a jump box VM
- **Virtual Network**: Dedicated subnets for AKS and Bastion

### Why This Approach?

✅ **No Jump Box VM needed** - Connect directly from your local machine  
✅ **Cost-effective** - Save on VM running costs  
✅ **Simplified management** - No need to maintain and patch jump box VMs  
✅ **Native kubectl experience** - Use kubectl directly from your workstation  
✅ **Secure** - Tunnel encrypted through Azure Bastion

## 🏗️ Architecture

```
                    ┌──────────────────────┐
                    │   Your Workstation   │
                    │   (Azure CLI +       │
                    │    kubectl)          │
                    └──────────┬───────────┘
                               │
                               │ Bastion Tunnel
                               ▼
┌──────────────────────────────────────────────────────┐
│              Azure Virtual Network                    │
│                  (10.0.0.0/16)                       │
│                                                       │
│  ┌────────────────────┐    ┌─────────────────────┐ │
│  │   AKS Subnet       │    │  Bastion Subnet     │ │
│  │  (10.0.0.0/22)     │    │  (10.0.4.0/26)      │ │
│  │                    │    │                     │ │
│  │ ┌────────────────┐ │    │ ┌─────────────────┐│ │
│  │ │ AKS Private    │ │    │ │ Azure Bastion   ││ │
│  │ │   Cluster      │ │    │ │                 ││ │
│  │ │                │◄┼────┼─┤ • Native Client ││ │
│  │ │ • Control      │ │    │ │   Tunneling     ││ │
│  │ │   Plane        │ │    │ │ • No Public IPs ││ │
│  │ │ • Worker Nodes │ │    │ │   on Resources  ││ │
│  │ └────────────────┘ │    │ └─────────────────┘│ │
│  └────────────────────┘    └─────────────────────┘ │
└──────────────────────────────────────────────────────┘
                        │
                        ▼
          ┌─────────────────────────┐
          │  Log Analytics          │
          │  Workspace              │
          │  (Monitoring & Logs)    │
          └─────────────────────────┘
```

**Connection Flow:**
1. User runs `az aks bastion` command from local workstation
2. Azure Bastion creates an encrypted tunnel to the AKS API server
3. kubectl commands route through localhost tunnel to private AKS cluster
4. No jump box VM required!

## ✅ Prerequisites

Before you begin, ensure you have:

1. **Azure Subscription** with sufficient permissions to create resources
2. **Azure CLI** installed (version 2.61.0 or later for AKS Bastion support)
   ```bash
   az --version
   az upgrade  # Upgrade if needed
   ```
3. **kubectl** installed on your local machine
   ```bash
   # macOS
   brew install kubectl
   
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```
4. **Bicep CLI** (comes with Azure CLI 2.20.0+)
   ```bash
   az bicep version
   ```
5. **jq** for JSON parsing (used in deploy.sh script)
   ```bash
   # macOS
   brew install jq
   
   # Linux
   sudo apt-get install jq
   ```
6. **Basic knowledge** of:
   - Azure Kubernetes Service (AKS)
   - Azure Bastion
   - Kubernetes fundamentals

### Required Azure Roles

- **Reader** role on the AKS cluster
- **Reader** role on the Azure Bastion resource
- **Reader** role on the virtual network

## 📦 What Gets Deployed

The Bicep template deploys the following resources:

| Resource Type | Resource Name | Purpose |
|--------------|---------------|---------|
| Resource Group | rg-aks-bastion-demo | Container for all resources |
| Virtual Network | vnet-aks-bastion-demo | Network isolation |
| AKS Cluster | aks-private-demo | Private Kubernetes cluster |
| Azure Bastion | bastion-aks-demo | Native client tunneling to AKS |
| Log Analytics Workspace | law-aks-* | Monitoring and diagnostics |
| Public IP Address | bastion-aks-demo-pip | Bastion public endpoint |

### AKS Cluster Configuration

- **Kubernetes Version**: 1.29.0
- **Network Plugin**: Azure CNI
- **Network Policy**: Azure Network Policy
- **Node Count**: 2 nodes (Standard_D2s_v3)
- **Private Cluster**: Enabled (API server not publicly accessible)
- **Monitoring**: Enabled with Log Analytics
- **Azure Policy Add-on**: Enabled

### Azure Bastion Configuration

- **SKU**: Standard
- **Native Client Support**: Enabled (for tunneling)
- **IP Connect**: Enabled
- **File Copy**: Enabled
- **Tunneling**: Enabled

## 🚀 Deployment Steps

### Option 1: Using the Deployment Script (Recommended)

1. **Clone or navigate to this directory**:
   ```bash
   cd AKS-Bastion
   ```

2. **Make the deployment script executable**:
   ```bash
   chmod +x deploy.sh
   ```

3. **Run the deployment**:
   ```bash
   ./deploy.sh
   ```

4. **Follow the prompts**:
   - Enter and confirm the admin password for the jump box VM
   - Wait for the deployment to complete (approximately 10-15 minutes)

### Option 2: Manual Deployment using Azure CLI

1. **Set variables**:
   ```bash
   RESOURCE_GROUP="rg-aks-bastion-demo"
   LOCATION="eastus"
   ```

2. **Create resource group**:
   ```bash
   az group create --name $RESOURCE_GROUP --location $LOCATION
   ```

3. **Deploy Bicep template**:
   ```bash
   az deployment group create \
     --resource-group $RESOURCE_GROUP \
     --template-file main.bicep \
     --parameters main.bicepparam
   ```

## 🔌 Connecting to the AKS Cluster

This is where the magic happens! Azure Bastion can now tunnel directly to your private AKS cluster.

### Step 1: Get AKS Credentials

From your **local workstation**:
```bash
RESOURCE_GROUP="rg-aks-bastion-demo"
AKS_CLUSTER_NAME="aks-private-demo"

az aks get-credentials \
  --admin \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP
```

### Step 2: Open Bastion Tunnel (Terminal 1)

In your **first terminal window**, start the Bastion tunnel:
```bash
# Get Bastion Resource ID
BASTION_ID=$(az network bastion show \
  --name bastion-aks-demo \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

# Open tunnel - this command keeps running
az aks bastion \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --admin \
  --bastion $BASTION_ID
```

**Note**: Leave this terminal running! It maintains the tunnel.

### Step 3: Configure kubectl (Terminal 2)

Open a **second terminal window** and configure kubectl to use the tunnel:

```bash
# Find the port that the tunnel is using
export BASTION_PORT=$(ps aux | sed -n 's/.*--port \([0-9]*\).*/\1/p' | head -1)

# Update kubeconfig to point to localhost tunnel
sed -i.bak "s|server: https://.*|server: https://localhost:${BASTION_PORT}|" ~/.kube/config

# Or on macOS if sed -i doesn't work:
sed -i '' "s|server: https://.*|server: https://localhost:${BASTION_PORT}|" ~/.kube/config
```

### Step 4: Use kubectl!

Now you can use kubectl commands from your local machine:
```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl cluster-info
```

**That's it!** You're now managing a private AKS cluster from your local workstation without any jump box VM.

## 🧪 Testing the Setup

### Deploy a Sample Application

1. **Create a namespace**:
   ```bash
   kubectl create namespace demo
   ```

2. **Deploy nginx**:
   ```bash
   kubectl run nginx --image=nginx --namespace demo
   ```

3. **Expose the pod**:
   ```bash
   kubectl expose pod nginx --port=80 --namespace demo
   ```

4. **Check the deployment**:
   ```bash
   kubectl get pods -n demo
   kubectl get svc -n demo
   ```

5. **Test connectivity** (from another pod):
   ```bash
   kubectl run curl-test --image=curlimages/curl -i --tty --rm --namespace demo -- sh
   # Inside the pod:
   curl http://nginx
   ```

### Verify Private Cluster Configuration

```bash
# Check if the cluster is private
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "apiServerAccessProfile"

# Get the private FQDN
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "privateFqdn" -o tsv
```

### View Logs in Log Analytics

1. Navigate to the Log Analytics workspace in the Azure Portal
2. Go to **Logs** section
3. Try these sample queries:

```kusto
// Container Insights - Pod inventory
KubePodInventory
| where TimeGenerated > ago(1h)
| summarize count() by Namespace, ControllerName
| order by count_ desc

// AKS Node Performance
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "K8SNode"
| summarize avg(CounterValue) by CounterName, Computer
```

## 🧹 Cleanup

### Using the Cleanup Script

```bash
chmod +x cleanup.sh
./cleanup.sh
```

### Manual Cleanup

```bash
az group delete --name rg-aks-bastion-demo --yes --no-wait
```

**Note**: Cleanup may take several minutes as all resources are deleted.

## 🔧 Troubleshooting

### Issue: `az aks bastion` command not found

**Solution**:
```bash
# Upgrade Azure CLI to the latest version
az upgrade

# Verify version (should be 2.61.0 or later)
az --version
```

### Issue: Bastion tunnel fails to connect

**Solution**:
- Verify Bastion is fully provisioned in Azure Portal
- Ensure Bastion has native client support enabled:
  ```bash
  az network bastion show --name bastion-aks-demo --resource-group rg-aks-bastion-demo --query enableTunneling
  ```
- Check that you have Reader permissions on the Bastion resource

### Issue: kubectl commands timeout after starting tunnel

**Solution**:
```bash
# Verify the tunnel is running
ps aux | grep "az aks bastion"

# Check that KUBECONFIG is updated correctly
cat ~/.kube/config | grep server

# It should show: server: https://localhost:<port>
```

### Issue: Deployment fails with quota or capacity errors

**Solution**:
- Check your subscription quotas
- Try a different region
- Try smaller VM sizes in the parameters file

### Issue: Port already in use when starting tunnel

**Solution**:
```bash
# Find and kill any existing tunnel process
ps aux | grep "az aks bastion" | grep -v grep | awk '{print $2}' | xargs kill

# Then restart the tunnel
az aks bastion --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --admin --bastion $BASTION_ID
```

### Issue: Connection drops after some time

**Solution**:
- This is expected if idle for too long
- Simply restart the tunnel using the command in Step 2
- Consider using tools like `watch kubectl get nodes` to keep the connection active

## 💰 Cost Considerations

Approximate monthly costs for this demo environment (US East region):

| Resource | Approximate Cost |
|----------|-----------------|
| AKS Cluster (2 x Standard_D2s_v3) | ~$140/month |
| Azure Bastion (Standard SKU) | ~$140/month |
| Log Analytics Workspace | ~$5-20/month (depends on ingestion) |
| Virtual Network | Free |
| **Total** | **~$285-300/month** |

**Comparison with Jump Box Approach:**
- **Old Method**: ~$355-370/month (includes $70/month jump box VM)
- **New Method**: ~$285-300/month
- **Savings**: ~$70/month by eliminating the jump box VM

**Cost-Saving Tips**:
- Use Basic Bastion SKU if tunneling features aren't needed for other resources
- Delete the entire demo when finished testing
- Consider AKS cost optimization features like node autoscaling

## 📚 Additional Resources

- [Connect to AKS Private Cluster using Azure Bastion (Official Docs)](https://learn.microsoft.com/azure/bastion/bastion-connect-to-aks-private-cluster)
- [AKS Private Cluster Documentation](https://learn.microsoft.com/azure/aks/private-clusters)
- [Azure Bastion Documentation](https://learn.microsoft.com/azure/bastion/bastion-overview)
- [Azure Bastion Native Client Support](https://learn.microsoft.com/azure/bastion/native-client)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [AKS Best Practices](https://learn.microsoft.com/azure/aks/best-practices)

## 🎓 Key Takeaways

✅ Azure Bastion now supports **direct tunneling to AKS private clusters**  
✅ **No jump box VM required** - connect from your local machine  
✅ Use native kubectl from your workstation  
✅ Cost-effective and simpler to manage  
✅ This is a **preview feature** as of December 2024

## 📝 License

This demo is provided as-is for educational purposes.

---

**Happy Learning! 🚀**
