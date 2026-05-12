#!/bin/bash
# =============================================================================
# VCluster Demo - Full Cleanup Script
# =============================================================================
# Deletes ALL vclusters and the host AKS infrastructure.
# Run this when you are finished with ALL demos.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DEFAULT_RG="rg-vcluster-demo"

echo -e "${RED}======================================${NC}"
echo -e "${RED}  VCluster Demo — Full Cleanup        ${NC}"
echo -e "${RED}======================================${NC}"
echo ""

read -p "  Enter resource group name [$DEFAULT_RG]: " RESOURCE_GROUP
RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RG}"

echo ""
echo -e "${YELLOW}The following will be permanently deleted:${NC}"
echo "  • All vclusters (namespaces: vc-basic, vc-tenant-a, vc-tenant-b, vc-limits, vc-sync, vc-ingress)"
echo "  • Resource group: $RESOURCE_GROUP (AKS cluster, VNet, Log Analytics)"
echo ""

read -p "  Type 'yes' to confirm: " -r
[[ ! "$REPLY" == "yes" ]] && { echo "Cleanup cancelled."; exit 0; }

echo ""

# --------------------------------------------------
# Delete vclusters if kubectl/vcluster is available
# --------------------------------------------------
if command -v vcluster &> /dev/null && kubectl config current-context &> /dev/null 2>&1; then
  echo -e "${YELLOW}Deleting all vclusters...${NC}"
  for vc in basic tenant-a tenant-b limits sync ingress; do
    ns="vc-${vc}"
    if kubectl get namespace "$ns" &> /dev/null 2>&1; then
      echo "  Deleting vcluster '$vc' in namespace '$ns'..."
      vcluster delete "$vc" --namespace "$ns" --delete-namespace 2>/dev/null || \
        kubectl delete namespace "$ns" --ignore-not-found
      echo -e "${GREEN}  ✓ Deleted $vc${NC}"
    fi
  done
  echo ""
fi

# --------------------------------------------------
# Delete Azure resource group
# --------------------------------------------------
echo -e "${YELLOW}Deleting Azure resource group '$RESOURCE_GROUP'...${NC}"
echo "  This may take 5-10 minutes..."

if az group exists --name "$RESOURCE_GROUP" | grep -q true; then
  az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait
  echo -e "${GREEN}  ✓ Deletion initiated (running in background)${NC}"
  echo ""
  echo "  Monitor progress:"
  echo "    az group show --name $RESOURCE_GROUP --query properties.provisioningState -o tsv"
else
  echo -e "${YELLOW}  Resource group '$RESOURCE_GROUP' not found — skipping${NC}"
fi

echo ""
echo -e "${GREEN}Cleanup complete.${NC}"
echo ""
