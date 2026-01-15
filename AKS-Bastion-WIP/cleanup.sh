#!/bin/bash

# Cleanup script for AKS Private Cluster with Azure Bastion Demo

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

# Configuration
RESOURCE_GROUP="rg-aks-bastion-demo"

print_message "$YELLOW" "=== Cleanup AKS Bastion Demo ==="
echo ""
print_message "$RED" "WARNING: This will delete the following resource group and all its resources:"
echo "  Resource Group: $RESOURCE_GROUP"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_message "$YELLOW" "Cleanup cancelled."
    exit 0
fi

# Check if resource group exists
if az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
    print_message "$YELLOW" "Deleting resource group: $RESOURCE_GROUP"
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    print_message "$GREEN" "✓ Resource group deletion initiated"
    print_message "$YELLOW" "Note: Deletion is running in the background. This may take several minutes."
else
    print_message "$YELLOW" "Resource group does not exist: $RESOURCE_GROUP"
fi

# Clean up local files
if [ -f "deployment-output.json" ]; then
    rm deployment-output.json
    print_message "$GREEN" "✓ Removed deployment-output.json"
fi

print_message "$GREEN" "=== Cleanup Complete ==="
