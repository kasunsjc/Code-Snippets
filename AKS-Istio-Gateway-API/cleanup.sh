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

# Configuration Variables
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-istio-gateway-demo}"

echo -e "${YELLOW}Resource Group to be deleted: $RESOURCE_GROUP${NC}"
echo ""
echo -e "${RED}WARNING: This will delete all resources in the resource group!${NC}"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Delete Kubernetes resources first (optional, as cluster will be deleted anyway)
echo -e "${YELLOW}Deleting Kubernetes resources...${NC}"
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    MANIFESTS_DIR="$SCRIPT_DIR/kubernetes-manifests"
    
    kubectl delete -f "$MANIFESTS_DIR/" --ignore-not-found=true || true
    echo -e "${GREEN}✓ Kubernetes resources deleted${NC}"
else
    echo -e "${YELLOW}Skipping Kubernetes resource cleanup (no access to cluster)${NC}"
fi
echo ""

# Clean up kubectl context
CLUSTER_NAME="${CLUSTER_NAME:-aks-istio-gateway-demo}"
echo -e "${YELLOW}Cleaning up kubectl context...${NC}"
CONTEXT_NAME=$(kubectl config get-contexts -o name | grep "$CLUSTER_NAME" || true)
if [[ -n "$CONTEXT_NAME" ]]; then
    kubectl config delete-context "$CONTEXT_NAME" || true
    echo -e "${GREEN}✓ Kubectl context removed: $CONTEXT_NAME${NC}"
else
    echo -e "${YELLOW}No kubectl context found for cluster: $CLUSTER_NAME${NC}"
fi
echo ""

# Delete resource group
echo -e "${YELLOW}Deleting resource group and all resources...${NC}"
az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Initiated!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Resource group deletion has been started in the background."
echo "You can check the status in the Azure Portal or with:"
echo "  az group show --name $RESOURCE_GROUP"
echo ""
