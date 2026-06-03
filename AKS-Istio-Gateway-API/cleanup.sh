#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}AKS Istio Gateway API Demo - Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    exit 1
fi

# Navigate to Terraform directory
cd terraform

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}No Terraform state found. Nothing to clean up.${NC}"
    exit 0
fi

# Get resource group name from Terraform output
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")

if [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve resource group name from Terraform output${NC}"
else
    echo -e "${YELLOW}Resource Group to be deleted: $RESOURCE_GROUP${NC}"
fi

echo ""
echo -e "${RED}WARNING: This will delete all resources created by this demo!${NC}"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Delete Kubernetes resources first (optional, as cluster will be deleted anyway)
echo -e "${YELLOW}Deleting Kubernetes resources...${NC}"
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    kubectl delete -f ../kubernetes-manifests/ --ignore-not-found=true || true
    echo -e "${GREEN}✓ Kubernetes resources deleted${NC}"
else
    echo -e "${YELLOW}Skipping Kubernetes resource cleanup (no access to cluster)${NC}"
fi
echo ""

# Destroy infrastructure
echo -e "${YELLOW}Destroying infrastructure with Terraform...${NC}"
terraform destroy -auto-approve

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "All resources have been deleted."
echo ""
