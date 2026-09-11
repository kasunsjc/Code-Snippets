#!/bin/bash
# ==============================================================
# AKS Node Auto-Provisioning (NAP) Demo — Terraform Deployment Script
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TF_VARS_FILE="$TF_DIR/terraform.tfvars"
NODEPOOLS_DIR="$SCRIPT_DIR/kubernetes-manifests/nodepools"
WORKLOADS_DIR="$SCRIPT_DIR/kubernetes-manifests/workloads"

RESOURCE_GROUP="rg-aks-node-autoprovision"
LOCATION="northeurope"
DEMO="none"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: ./deploy.sh [options]

Options:
  --demo <none|general|memory|spot|arm64|static|all>  Apply NodePools + a matching sample
                                                        workload after the cluster is ready.
  --help                                                Show this help.

Examples:
  ./deploy.sh
  ./deploy.sh --demo general
  ./deploy.sh --demo all
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo)
      [[ $# -ge 2 ]] || { echo "ERROR: --demo requires a value."; usage; exit 1; }
      DEMO="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument '$1'"
      usage
      exit 1
      ;;
  esac
done

if [[ "$DEMO" != "none" && "$DEMO" != "general" && "$DEMO" != "memory" && "$DEMO" != "spot" && "$DEMO" != "arm64" && "$DEMO" != "static" && "$DEMO" != "all" ]]; then
  echo -e "${RED}ERROR: Invalid --demo value '$DEMO'.${NC} Expected one of: none, general, memory, spot, arm64, static, all."
  exit 1
fi

echo "=================================================="
echo "  AKS Node Auto-Provisioning (NAP) Demo — Deploy"
echo "=================================================="
echo "Resource Group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Demo workload  : $DEMO"
echo ""

echo "Checking prerequisites..."
for cmd in az kubectl terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}ERROR: '$cmd' is not installed or not in PATH.${NC}"
    exit 1
  fi
done

AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
echo "  Azure CLI version: $AZ_VERSION (NAP requires 2.76.0+)"

echo -e "${GREEN}Checking Azure CLI login...${NC}"
az account show --output none || { echo -e "${RED}ERROR: Not logged in to Azure. Run 'az login'.${NC}"; exit 1; }

echo ""
echo "Retrieving current user Object ID for role assignments..."
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [[ -z "$USER_OBJECT_ID" ]]; then
  echo -e "${YELLOW}  Warning: Could not retrieve user Object ID. Optional role assignment will be skipped.${NC}"
fi

echo ""
echo "[1/5] Initializing Terraform..."
terraform -chdir="$TF_DIR" init

echo ""
echo "[2/5] Applying Terraform infrastructure (this can take ~10 minutes)..."
if [[ -f "$TF_VARS_FILE" ]]; then
  terraform -chdir="$TF_DIR" apply -auto-approve -var-file="$TF_VARS_FILE" -var="user_object_id=${USER_OBJECT_ID:-}"
else
  terraform -chdir="$TF_DIR" apply -auto-approve \
    -var="resource_group_name=$RESOURCE_GROUP" \
    -var="location=$LOCATION" \
    -var="user_object_id=${USER_OBJECT_ID:-}"
fi

echo ""
echo "[3/5] Reading Terraform outputs..."
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

AKS_NAME=$(tf_out aks_cluster_name)
RG_NAME=$(tf_out resource_group_name)
NODE_RG=$(tf_out node_resource_group)
LAW_NAME=$(tf_out log_analytics_workspace_name)

echo "  AKS cluster       : $AKS_NAME"
echo "  Resource group    : $RG_NAME"
echo "  Node resource grp : $NODE_RG"
echo "  Log Analytics ws  : $LAW_NAME"

echo ""
echo "[4/5] Fetching kubeconfig..."
az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing

echo ""
echo "[5/5] Applying custom NodePools (NAP will reuse the built-in 'default' AKSNodeClass)..."
kubectl apply -f "$NODEPOOLS_DIR"

apply_workload() {
  echo "  Applying workload: $1"
  kubectl apply -f "$WORKLOADS_DIR/$1"
}

case "$DEMO" in
  general) apply_workload "01-general-purpose-workload.yaml" ;;
  memory)  apply_workload "02-memory-intensive-workload.yaml" ;;
  spot)    apply_workload "03-spot-workload.yaml" ;;
  arm64)   apply_workload "04-arm64-workload.yaml" ;;
  static)  echo "  Static NodePool 'static-critical' already applied with fixed replicas: 2" ;;
  all)
    apply_workload "01-general-purpose-workload.yaml"
    apply_workload "02-memory-intensive-workload.yaml"
    apply_workload "03-spot-workload.yaml"
    apply_workload "04-arm64-workload.yaml"
    ;;
  none) echo "  Skipping sample workload deployment (--demo none)." ;;
esac

echo ""
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Watch NAP provision nodes for pending pods:"
echo "  kubectl get nodepools"
echo "  kubectl get nodeclaims -o wide -w"
echo "  kubectl get nodes -L karpenter.sh/nodepool,karpenter.azure.com/sku-family,kubernetes.io/arch"
echo ""
echo "Watch Karpenter events:"
echo "  kubectl get events --field-selector source=karpenter-events"
echo ""
echo "Query control plane logs in Log Analytics ($LAW_NAME):"
echo "  AKSControlPlane | where Category == \"karpenter-events\""
