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
  --demo <none|general|memory|arm64|static|affinity|priority|all>  Apply NodePools + a
                                                        matching sample workload after the
                                                        cluster is ready.
  --help                                                Show this help.

Examples:
  ./deploy.sh
  ./deploy.sh --demo general
  ./deploy.sh --demo affinity
  ./deploy.sh --demo priority
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

VALID_DEMOS=(none general memory arm64 static affinity priority all)
IS_VALID_DEMO=false
for valid_demo in "${VALID_DEMOS[@]}"; do
  if [[ "$DEMO" == "$valid_demo" ]]; then
    IS_VALID_DEMO=true
    break
  fi
done

if [[ "$IS_VALID_DEMO" != "true" ]]; then
  echo -e "${RED}ERROR: Invalid --demo value '$DEMO'.${NC} Expected one of: ${VALID_DEMOS[*]}."
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
echo "Retrieving principal Object ID for optional role assignment..."
PRINCIPAL_OBJECT_ID=""
ACCOUNT_TYPE=$(az account show --query user.type -o tsv 2>/dev/null || echo "")
ACCOUNT_NAME=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
if [[ "$ACCOUNT_TYPE" == "user" ]]; then
  PRINCIPAL_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
elif [[ "$ACCOUNT_TYPE" == "servicePrincipal" && -n "$ACCOUNT_NAME" ]]; then
  PRINCIPAL_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_NAME" --query id -o tsv 2>/dev/null || echo "")
fi
if [[ -z "$PRINCIPAL_OBJECT_ID" ]]; then
  echo -e "${YELLOW}  Warning: Could not auto-detect principal Object ID. Optional role assignment will be skipped unless set in terraform.tfvars.${NC}"
fi

PRINCIPAL_OBJECT_ID_ARG=()
if [[ -n "$PRINCIPAL_OBJECT_ID" ]]; then
  if [[ -f "$TF_VARS_FILE" ]] && grep -Eq '^[[:space:]]*(principal_object_id|user_object_id)[[:space:]]*=' "$TF_VARS_FILE"; then
    echo "  terraform.tfvars defines principal object id; using that value."
  else
    PRINCIPAL_OBJECT_ID_ARG=(-var="principal_object_id=${PRINCIPAL_OBJECT_ID}")
  fi
fi

echo ""
echo "[1/5] Initializing Terraform..."
terraform -chdir="$TF_DIR" init

echo ""
echo "[2/5] Applying Terraform infrastructure (this can take ~10 minutes)..."
if [[ -f "$TF_VARS_FILE" ]]; then
  terraform -chdir="$TF_DIR" apply -auto-approve -var-file="$TF_VARS_FILE" "${PRINCIPAL_OBJECT_ID_ARG[@]}"
else
  terraform -chdir="$TF_DIR" apply -auto-approve \
    -var="resource_group_name=$RESOURCE_GROUP" \
    -var="location=$LOCATION" \
    "${PRINCIPAL_OBJECT_ID_ARG[@]}"
fi

echo ""
echo "[3/5] Reading Terraform outputs..."
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

AKS_NAME=$(tf_out aks_cluster_name)
RG_NAME=$(tf_out resource_group_name)
NODE_RG=$(tf_out node_resource_group)
LAW_NAME=$(tf_out log_analytics_workspace_name)
AKS_LOCATION=$(az aks show --resource-group "$RG_NAME" --name "$AKS_NAME" --query location -o tsv)
PRIORITY_SUPPORTED=false
if [[ "$AKS_LOCATION" == "northeurope" ]]; then
  PRIORITY_SUPPORTED=true
fi

echo "  AKS cluster       : $AKS_NAME"
echo "  Resource group    : $RG_NAME"
echo "  Node resource grp : $NODE_RG"
echo "  Log Analytics ws  : $LAW_NAME"

echo ""
echo "[4/5] Fetching kubeconfig..."
az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing

echo ""
echo "[5/5] Applying custom NodePools (NAP will reuse the built-in 'default' AKSNodeClass)..."
apply_nodepool() {
  kubectl apply -f "$NODEPOOLS_DIR/$1"
}

case "$DEMO" in
  none) echo "  Skipping NodePool manifests (--demo none)." ;;
  general)  apply_nodepool "01-general-purpose-nodepool.yaml" ;;
  memory)   apply_nodepool "02-memory-optimized-nodepool.yaml" ;;
  arm64)    apply_nodepool "04-arm64-nodepool.yaml" ;;
  static)   apply_nodepool "05-static-nodepool.yaml" ;;
  affinity) apply_nodepool "01-general-purpose-nodepool.yaml" ;;
  priority)
    if [[ "$PRIORITY_SUPPORTED" == "true" ]]; then
      apply_nodepool "06-priority-zone-nodepool.yaml"
    else
      echo -e "${YELLOW}Skipping priority NodePool outside northeurope.${NC}"
    fi
    ;;
  all)
    if [[ "$PRIORITY_SUPPORTED" == "true" ]]; then
      kubectl apply -f "$NODEPOOLS_DIR"
    else
      echo -e "${YELLOW}Skipping priority NodePool outside northeurope.${NC}"
      for nodepool_manifest in "$NODEPOOLS_DIR"/*.yaml; do
        if [[ "$(basename "$nodepool_manifest")" == "06-priority-zone-nodepool.yaml" ]]; then
          continue
        fi
        kubectl apply -f "$nodepool_manifest"
      done
    fi
    ;;
esac

apply_workload() {
  echo "  Applying workload: $1"
  kubectl apply -f "$WORKLOADS_DIR/$1"
}

apply_priority_workloads() {
  if [[ "$PRIORITY_SUPPORTED" != "true" ]]; then
    echo -e "${YELLOW}Skipping priority demo: currently supported only in 'northeurope' because manifests are pinned to northeurope-1.${NC}"
    return 0
  fi

  apply_workload "06-priorityclass-workload.yaml"
  # Give low-priority pods a head start, but continue even if they don't fully roll out
  # so preemption/provisioning-order behavior can still be demonstrated.
  kubectl rollout status deployment/priority-low-demo --timeout=60s >/dev/null 2>&1 || true
  apply_workload "07-priorityclass-high-workload.yaml"
}

case "$DEMO" in
  general)  apply_workload "01-general-purpose-workload.yaml" ;;
  memory)   apply_workload "02-memory-intensive-workload.yaml" ;;
  arm64)    apply_workload "04-arm64-workload.yaml" ;;
  static)   echo "  Static NodePool 'static-critical' already applied with fixed replicas: 2" ;;
  affinity) apply_workload "05-affinity-antiaffinity-workload.yaml" ;;
  priority) apply_priority_workloads ;;
  all)
    apply_workload "01-general-purpose-workload.yaml"
    apply_workload "02-memory-intensive-workload.yaml"
    apply_workload "04-arm64-workload.yaml"
    apply_workload "05-affinity-antiaffinity-workload.yaml"
    apply_priority_workloads
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
