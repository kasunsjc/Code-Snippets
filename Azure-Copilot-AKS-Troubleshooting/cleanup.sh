#!/bin/bash

# Cleanup script for Azure Copilot AKS Troubleshooting Demo
# Removes the entire resource group and all resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

RESOURCE_GROUP_NAME="rg-copilot-aks-demo"

print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

echo ""
echo "=============================================="
echo "  Cleanup: Azure Copilot AKS Demo"
echo "=============================================="
echo ""

print_warning "This will delete the resource group '$RESOURCE_GROUP_NAME' and ALL resources in it."
echo ""
read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Remove kubectl context
print_message "Removing kubectl context..."
kubectl config delete-context "copilot-aks-demo" 2>/dev/null || true
kubectl config delete-cluster "copilot-aks-demo" 2>/dev/null || true

# Delete resource group
print_message "Deleting resource group: $RESOURCE_GROUP_NAME (this takes a few minutes)..."
az group delete \
    --name "$RESOURCE_GROUP_NAME" \
    --yes \
    --no-wait

print_message "Resource group deletion initiated (running in background)."
echo ""
echo "  To check progress:"
echo "  az group show --name $RESOURCE_GROUP_NAME --query provisioningState -o tsv"
echo ""
