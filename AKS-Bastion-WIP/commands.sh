# Azure CLI commands for AKS Private Cluster with Bastion Demo
# These commands can be run individually for testing and demonstration

# Variables
RESOURCE_GROUP="rg-aks-bastion-demo"
LOCATION="eastus"
AKS_CLUSTER_NAME="aks-private-demo"
BASTION_NAME="bastion-aks-demo"

# ============================================
# DEPLOYMENT COMMANDS
# ============================================

# 1. Create Resource Group
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION

# 2. Deploy the infrastructure using Bicep
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --name aks-bastion-deployment \
    --template-file main.bicep \
    --parameters main.bicepparam

# 3. Get deployment outputs
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name aks-bastion-deployment \
    --query properties.outputs

# ============================================
# BASTION CONNECTION COMMANDS (Preview Feature)
# ============================================

# 4. Get AKS credentials
az aks get-credentials \
    --admin \
    --name $AKS_CLUSTER_NAME \
    --resource-group $RESOURCE_GROUP

# 5. Open tunnel to AKS cluster using Azure Bastion
# This command keeps running - leave it open in one terminal
az aks bastion \
    --name $AKS_CLUSTER_NAME \
    --resource-group $RESOURCE_GROUP \
    --admin \
    --bastion $(az network bastion show --name $BASTION_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)

# 6. In a NEW terminal, update KUBECONFIG to use the Bastion tunnel
export BASTION_PORT=$(ps aux | sed -n 's/.*--port \([0-9]*\).*/\1/p' | head -1)
sed -i "s|server: https://.*|server: https://localhost:${BASTION_PORT}|" ~/.kube/config

# 7. Now you can use kubectl commands
kubectl get nodes
kubectl get pods --all-namespaces
kubectl cluster-info

# ============================================
# DEPLOY SAMPLE APPLICATION
# ============================================

# 8. Deploy a sample application
kubectl create namespace demo
kubectl run nginx --image=nginx --namespace demo
kubectl expose pod nginx --port=80 --namespace demo
kubectl get pods -n demo

# ============================================
# MONITORING AND DIAGNOSTICS
# ============================================

# 9. View AKS cluster details
az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --output table

# 10. Check if cluster is private
az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "apiServerAccessProfile"

# 11. Get private FQDN
az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "privateFqdn" -o tsv

# 12. View Bastion details
az network bastion show \
    --name $BASTION_NAME \
    --resource-group $RESOURCE_GROUP

# 13. List all resources in the resource group
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table

# ============================================
# CLEANUP
# ============================================

# 14. Delete the entire resource group
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait
