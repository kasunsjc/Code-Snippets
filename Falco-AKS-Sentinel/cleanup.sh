#!/bin/bash
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-falco-sentinel-demo}"
NODE_RG="${NODE_RG:-rg-falcosec-nodes}"

echo "==> Deleting resource group: $RESOURCE_GROUP"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "==> Deleting node resource group: $NODE_RG (if it exists)"
az group delete --name "$NODE_RG" --yes --no-wait 2>/dev/null || true

echo "==> Removing local kubeconfig context..."
kubectl config delete-context "${CLUSTER_NAME:-falcosec-aks}" 2>/dev/null || true
kubectl config delete-cluster "${CLUSTER_NAME:-falcosec-aks}" 2>/dev/null || true

echo "==> Cleanup initiated. Deletion runs asynchronously in Azure."
echo "    Monitor with: az group show -n $RESOURCE_GROUP --query properties.provisioningState -o tsv"
