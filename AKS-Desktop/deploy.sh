#!/bin/bash
set -euo pipefail

# Configuration
RESOURCE_GROUP="rg-aks-automatic-demo"
LOCATION="swedencentral"
DEPLOYMENT_NAME="aks-automatic-deployment"

echo "=== AKS Automatic Cluster Deployment ==="

# Create Resource Group
echo "Creating resource group: $RESOURCE_GROUP in $LOCATION..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table

# Get current user object ID for Grafana Admin role
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")

if [ -z "$USER_OBJECT_ID" ]; then
  echo "Warning: Could not retrieve user object ID. Grafana Admin role will not be assigned."
fi

# Deploy Bicep template using parameter file
echo "Deploying AKS Automatic cluster with monitoring..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --parameters main.bicepparam \
  --parameters userId="$USER_OBJECT_ID" \
  --output table

# Get outputs
echo ""
echo "=== Deployment Outputs ==="
AKS_NAME=$(az deployment group show --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT_NAME" --query 'properties.outputs.aksClusterName.value' -o tsv)
GRAFANA_URL=$(az deployment group show --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT_NAME" --query 'properties.outputs.grafanaEndpoint.value' -o tsv)

echo "AKS Cluster: $AKS_NAME"
echo "Grafana URL: $GRAFANA_URL"

# Get AKS credentials (--format azure required for Azure RBAC-enabled clusters)
echo ""
echo "Getting AKS credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing

echo ""
echo "=== Deployment Complete ==="
echo "Run 'kubectl get nodes' to verify cluster access"
echo "Access Grafana at: $GRAFANA_URL"
