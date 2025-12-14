#!/bin/bash

# AKS Fleet Manager Demo - Cleanup Script
# This script removes all resources created by the demo

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="rg-aks-fleet-demo"

echo -e "${RED}======================================${NC}"
echo -e "${RED}AKS Fleet Manager Demo Cleanup${NC}"
echo -e "${RED}======================================${NC}"
echo ""

echo -e "${YELLOW}This will delete the following:${NC}"
echo "  - Resource Group: $RESOURCE_GROUP"
echo "  - Fleet Manager and all member clusters"
echo "  - All deployed applications and resources"
echo "  - Virtual networks and networking resources"
echo ""

read -p "Are you sure you want to delete all resources? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "${YELLOW}Starting cleanup...${NC}"
echo ""

# Check if resource group exists
if az group exists --name $RESOURCE_GROUP; then
    echo -e "${YELLOW}Deleting resource group: $RESOURCE_GROUP${NC}"
    echo "This may take several minutes..."
    
    az group delete \
        --name $RESOURCE_GROUP \
        --yes \
        --no-wait
    
    echo -e "${GREEN}✓ Resource group deletion initiated${NC}"
    echo ""
    echo "The resource group is being deleted in the background."
    echo "You can check the status with:"
    echo "  az group show --name $RESOURCE_GROUP"
else
    echo -e "${YELLOW}Resource group $RESOURCE_GROUP does not exist${NC}"
fi

# Clean up kubectl contexts
echo -e "${YELLOW}Cleaning up kubectl contexts...${NC}"
CONTEXTS=$(kubectl config get-contexts -o name | grep -E "fleet-hub|aks-member")

if [ ! -z "$CONTEXTS" ]; then
    for context in $CONTEXTS; do
        echo "  Removing context: $context"
        kubectl config delete-context $context 2>/dev/null || true
    done
    echo -e "${GREEN}✓ Kubectl contexts cleaned up${NC}"
else
    echo -e "${YELLOW}No fleet-related contexts found${NC}"
fi

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
