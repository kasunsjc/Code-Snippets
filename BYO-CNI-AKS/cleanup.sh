#!/bin/bash

# Cleanup script for BYO CNI AKS with Cilium Demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

RESOURCE_GROUP_NAME="rg-byocni-cilium-demo"

print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

echo ""
echo "=========================================="
echo "   BYO CNI AKS + Cilium - Cleanup"
echo "=========================================="
echo ""

print_warning "This will delete ALL resources in resource group: $RESOURCE_GROUP_NAME"
echo ""
read -p "Are you sure you want to continue? (y/N): " -r REPLY
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_message "Cleanup cancelled."
    exit 0
fi

# Remove kubectl context
AKS_CLUSTER_NAME=$(az aks list --resource-group "$RESOURCE_GROUP_NAME" --query "[0].name" --output tsv 2>/dev/null || echo "")
if [ -n "$AKS_CLUSTER_NAME" ]; then
    print_message "Removing kubectl context for $AKS_CLUSTER_NAME..."
    kubectl config delete-context "$AKS_CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-cluster "$AKS_CLUSTER_NAME" 2>/dev/null || true
fi

# Delete resource group
print_message "Deleting resource group: $RESOURCE_GROUP_NAME..."
az group delete \
    --name "$RESOURCE_GROUP_NAME" \
    --yes \
    --no-wait

print_message "Resource group deletion initiated (running in background)."
print_message "Use 'az group show -n $RESOURCE_GROUP_NAME' to check deletion status."
echo ""
print_message "Cleanup complete!"
