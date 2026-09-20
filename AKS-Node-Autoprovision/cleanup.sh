#!/bin/bash
# ==============================================================
# AKS Node Auto-Provisioning (NAP) Demo — Cleanup Script
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TF_VARS_FILE="$TF_DIR/terraform.tfvars"
NODEPOOLS_DIR="$SCRIPT_DIR/kubernetes-manifests/nodepools"
WORKLOADS_DIR="$SCRIPT_DIR/kubernetes-manifests/workloads"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "  AKS Node Auto-Provisioning (NAP) Demo — Cleanup"
echo "=================================================="

read -r -p "This will destroy the demo cluster and all resources. Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || true
}

RG_NAME="$(tf_out resource_group_name)"
AKS_NAME="$(tf_out aks_cluster_name)"

if [[ -n "$RG_NAME" ]] && command -v az &>/dev/null; then
  CONTAINER_INSIGHTS_SOLUTION_IDS=$(az resource list \
    --resource-group "$RG_NAME" \
    --resource-type "Microsoft.OperationsManagement/solutions" \
    --query "[?contains(name, 'ContainerInsights')].id" \
    -o tsv 2>/dev/null || true)

  if [[ -n "$CONTAINER_INSIGHTS_SOLUTION_IDS" ]]; then
    echo -e "${YELLOW}Deleting ContainerInsights solution resources created outside Terraform state...${NC}"
    while IFS= read -r resource_id; do
      if [[ -n "$resource_id" ]]; then
        az resource delete --ids "$resource_id" || true
      fi
    done <<< "$CONTAINER_INSIGHTS_SOLUTION_IDS"
  fi
fi

if command -v az &>/dev/null && command -v kubectl &>/dev/null && [[ -n "$RG_NAME" ]] && [[ -n "$AKS_NAME" ]]; then
  echo -e "${YELLOW}Targeting AKS context from Terraform outputs before kubectl cleanup...${NC}"
  az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing >/dev/null
fi

if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
  echo ""
  echo -e "${YELLOW}Removing sample workloads and NodePools first (graceful NAP node teardown)...${NC}"
  kubectl delete -f "$WORKLOADS_DIR" --ignore-not-found --timeout=60s || true
  kubectl delete -f "$NODEPOOLS_DIR" --ignore-not-found --timeout=120s || true
else
  echo -e "${YELLOW}Skipping kubectl cleanup step (cluster not reachable).${NC}"
fi

echo ""
echo "Destroying Terraform-managed infrastructure..."
if [[ -f "$TF_VARS_FILE" ]]; then
  terraform -chdir="$TF_DIR" destroy -auto-approve -var-file="$TF_VARS_FILE"
else
  terraform -chdir="$TF_DIR" destroy -auto-approve
fi

echo ""
echo "Removing local Terraform state and provider cache..."
rm -rf "$TF_DIR/.terraform" "$TF_DIR/terraform.tfstate" "$TF_DIR/terraform.tfstate.backup"

echo -e "${GREEN}Cleanup complete.${NC}"
