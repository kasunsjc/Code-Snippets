#!/bin/bash
set -euo pipefail

RESOURCE_GROUP="rg-aks-desktop-ai-demo"
LOCATION="swedencentral"
DEPLOYMENT_NAME="aks-desktop-ai-demo"
CLUSTER_NAME="aks-desktop-ai-demo"

echo "=== AKS Desktop AI Troubleshooting Demo ==="

echo "Creating resource group: $RESOURCE_GROUP in $LOCATION..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table

echo "Deploying default AKS cluster..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file main.bicep \
  --parameters clusterName="$CLUSTER_NAME" \
  --output table

AKS_NAME=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --query 'properties.outputs.aksClusterName.value' -o tsv)

echo "AKS cluster created: $AKS_NAME"

echo "Fetching AKS credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing

echo ""
echo "Demo is ready."
echo "Run: kubectl get nodes"
echo "Then: kubectl create namespace ai-demo && kubectl apply -f broken-app-demo.yaml"
