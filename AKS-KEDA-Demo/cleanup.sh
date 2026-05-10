#!/bin/bash
# ==============================================================
# AKS KEDA Demo — Cleanup Script
# Removes all demo resources to stop Azure costs.
# ==============================================================
set -euo pipefail

RESOURCE_GROUP="rg-aks-keda-demo"
AKS_NAME="aks-keda-demo"

echo "=================================================="
echo "  AKS KEDA Demo — Cleanup"
echo "=================================================="
echo "This will delete resource group: $RESOURCE_GROUP"
echo "All resources inside it will be permanently removed."
echo ""
read -r -p "Are you sure? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# ---- Remove kubeconfig entries ----
echo ""
echo "Removing kubeconfig entries for $AKS_NAME..."
kubectl config delete-context "$AKS_NAME" 2>/dev/null \
  && echo "  Deleted context: $AKS_NAME" \
  || echo "  Context not found, skipping."

kubectl config delete-cluster "$AKS_NAME" 2>/dev/null \
  && echo "  Deleted cluster: $AKS_NAME" \
  || echo "  Cluster entry not found, skipping."

# ---- Delete Resource Group ----
echo ""
echo "Deleting resource group: $RESOURCE_GROUP ..."
echo "(This runs in the background and may take several minutes.)"
az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait

echo ""
echo "=================================================="
echo "  Cleanup Initiated"
echo "=================================================="
echo "Resource group deletion is running in the background."
echo "Run the following to check status:"
echo "  az group show --name $RESOURCE_GROUP --query properties.provisioningState -o tsv"
