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
AKS_CLUSTER_NAMES=""

discover_aks_clusters() {
  if ! command -v az &> /dev/null; then
    return
  fi
  AKS_CLUSTER_NAMES=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
}

cleanup_aks_contexts() {
  if ! command -v kubectl &> /dev/null; then
    return
  fi

  echo -e "${YELLOW}Removing AKS kubeconfig contexts...${NC}"
  if [[ -z "$AKS_CLUSTER_NAMES" ]]; then
    echo "  No AKS clusters discovered in resource group '$RESOURCE_GROUP'."
    return
  fi

  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    kubectl config delete-context "$cluster" 2>/dev/null || true
    kubectl config delete-cluster "$cluster" 2>/dev/null || true
    kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${cluster}" 2>/dev/null || true
    kubectl config delete-user "clusterAdmin_${RESOURCE_GROUP}_${cluster}" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Removed kubeconfig entries for $cluster${NC}"
  done <<< "$AKS_CLUSTER_NAMES"
}

echo -e "${RED}======================================${NC}"
echo -e "${RED}  VCluster Demo — Full Cleanup        ${NC}"
echo -e "${RED}======================================${NC}"
echo ""

read -p "  Enter resource group name [$DEFAULT_RG]: " RESOURCE_GROUP
# Read user input for resource group name with a default value
# If user just presses Enter, DEFAULT_RG is used
RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RG}"

echo ""
echo -e "${YELLOW}The following will be permanently deleted:${NC}"
echo "  • All vclusters (namespaces: vc-basic, vc-tenant-a, vc-tenant-b, vc-limits, vc-sync, vc-ingress)"
echo "  • Resource group: $RESOURCE_GROUP (AKS cluster, VNet, Log Analytics)"
echo ""

# Require explicit user confirmation to prevent accidental deletion
# read -r: read raw input (don't interpret backslashes)
read -p "  Type 'yes' to confirm: " -r
# Only proceed if user types exactly "yes" (case-sensitive)
[[ ! "$REPLY" == "yes" ]] && { echo "Cleanup cancelled."; exit 0; }

echo ""

# --------------------------------------------------
# Delete vclusters if kubectl/vcluster is available
# --------------------------------------------------
# Check prerequisites: vcluster CLI must be installed and kubectl must have an active context
# This section is optional; if tools aren't available, skip to Azure resource cleanup
if command -v vcluster &> /dev/null && kubectl config current-context &> /dev/null 2>&1; then
  echo -e "${YELLOW}Deleting all vclusters...${NC}"
  # Loop through all demo vcluster names
  # For each one, check if its namespace exists and delete it
  # vcluster delete: removes the vcluster StatefulSet, associated resources, and optionally the namespace
  for vc in basic tenant-a tenant-b limits sync ingress; do
    ns="vc-${vc}"
    # Check if namespace exists on the host cluster
    # 2>&1: redirect stderr to stdout to suppress error messages
    if kubectl get namespace "$ns" &> /dev/null 2>&1; then
      echo "  Deleting vcluster '$vc' in namespace '$ns'..."
      # vcluster delete --delete-namespace: also delete the host namespace (cleans up completely)
      # 2>/dev/null || ...: if vcluster command fails, fall back to kubectl delete namespace
      # This provides graceful degradation if vcluster CLI isn't responsive
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
# Resource groups are containers for all Azure resources
# Deleting the RG deletes: AKS cluster, VNet, public IP, load balancer, Log Analytics, etc.
echo -e "${YELLOW}Deleting Azure resource group '$RESOURCE_GROUP'...${NC}"
echo "  This may take 5-10 minutes..."

# First check if the resource group exists
if az group exists --name "$RESOURCE_GROUP" | grep -q true; then
  discover_aks_clusters
  # az group delete: delete the resource group and all resources in it
  # --yes: skip confirmation prompt
  # --no-wait: submit delete request and return immediately (delete happens in background)
  az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait
  echo -e "${GREEN}  ✓ Deletion initiated (running in background)${NC}"
  echo ""
  echo "  Monitor progress:"
  # Command to check deletion status (provisioning state changes from Deleting to Deleted)
  echo "    az group show --name $RESOURCE_GROUP --query properties.provisioningState -o tsv"
else
  echo -e "${YELLOW}  Resource group '$RESOURCE_GROUP' not found — skipping${NC}"
fi

cleanup_aks_contexts

echo ""
echo -e "${GREEN}Cleanup complete.${NC}"
echo ""
