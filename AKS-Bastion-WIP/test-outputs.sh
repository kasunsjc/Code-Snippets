#!/bin/bash

# Test script to verify deployment outputs can be retrieved

RESOURCE_GROUP="rg-aks-bastion-demo"
DEPLOYMENT_NAME=$(az deployment group list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)

if [ -z "$DEPLOYMENT_NAME" ]; then
    echo "No deployments found in resource group: $RESOURCE_GROUP"
    exit 1
fi

echo "Found deployment: $DEPLOYMENT_NAME"
echo ""
echo "Fetching outputs..."

# Method 1: Query deployment directly
echo "=== Method 1: Query deployment ==="
az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --query "properties.outputs" \
    --output json

echo ""
echo "=== Method 2: List resources ==="
echo "AKS Clusters:"
az aks list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Location:location}" -o table

echo ""
echo "Bastion Hosts:"
az network bastion list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Id:id}" -o table

echo ""
echo "Virtual Networks:"
az network vnet list --resource-group "$RESOURCE_GROUP" --query "[].name" -o table
