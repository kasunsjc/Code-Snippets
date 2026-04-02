#!/bin/bash
set -euo pipefail

# Configuration
RESOURCE_GROUP="rg-aks-automatic-demo"
AKS_NAME="aks-automatic-demo"

echo "=== AKS Automatic Cluster Cleanup ==="

# Remove kubeconfig context and cluster entries
echo "Removing kubeconfig entries for $AKS_NAME..."
kubectl config delete-context "$AKS_NAME" 2>/dev/null && echo "  Deleted context: $AKS_NAME" || echo "  Context not found, skipping."
kubectl config delete-cluster "$AKS_NAME" 2>/dev/null && echo "  Deleted cluster: $AKS_NAME" || echo "  Cluster entry not found, skipping."
kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${AKS_NAME}" 2>/dev/null && echo "  Deleted user: clusterUser_${RESOURCE_GROUP}_${AKS_NAME}" || echo "  User entry not found, skipping."

# Delete resource group (removes all resources)
echo ""
echo "Deleting resource group: $RESOURCE_GROUP (this may take several minutes)..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo ""
echo "=== Cleanup Initiated ==="
echo "Resource group deletion is running in the background."
echo "Run 'az group show -n $RESOURCE_GROUP' to check status."
