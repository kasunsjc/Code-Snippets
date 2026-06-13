#!/bin/bash
# ==============================================================
# AKS KEDA Demo — Terraform Cleanup Script
# ==============================================================
set -euo pipefail

RESOURCE_GROUP="rg-aks-keda-demo"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/terraform"
TF_VARS_FILE="$TF_DIR/terraform.tfvars"
AKS_NAME="aks-keda-demo"

TF_VAR_ARGS=()
if [[ -f "$TF_VARS_FILE" ]]; then
  TF_VAR_ARGS+=("-var-file=$TF_VARS_FILE")
fi

echo "=================================================="
echo "  AKS KEDA Demo — Cleanup"
echo "=================================================="
echo "This will run terraform destroy for: $RESOURCE_GROUP"
echo ""
read -r -p "Are you sure? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

for cmd in terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

echo ""
echo "[1/2] Destroying Terraform-managed resources..."
terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" destroy \
  -auto-approve \
  "${TF_VAR_ARGS[@]}" \
  -var="resource_group_name=$RESOURCE_GROUP"

echo ""
echo "[2/2] Cleaning local kubeconfig entries..."
if command -v kubectl &>/dev/null; then
  kubectl config delete-context "$AKS_NAME" 2>/dev/null || true
  kubectl config delete-cluster "$AKS_NAME" 2>/dev/null || true
else
  echo "kubectl not found; skipping local kubeconfig cleanup."
fi

echo ""
echo "=================================================="
echo "  Cleanup Complete"
echo "=================================================="
