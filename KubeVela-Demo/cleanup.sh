#!/bin/bash
# ==============================================================
# KubeVela on AKS - Cleanup Script
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TF_VARS_FILE="$TF_DIR/terraform.tfvars"

if ! command -v terraform &>/dev/null; then
  echo "ERROR: 'terraform' is not installed or not in PATH."
  exit 1
fi

echo "=================================================="
echo "  KubeVela on AKS - Cleanup"
echo "=================================================="
echo "This destroys the Terraform-managed AKS cluster and resource groups."
read -r -p "Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

cluster_name=$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || true)

echo ""
echo "[1/3] Initializing Terraform..."
terraform -chdir="$TF_DIR" init

echo ""
echo "[2/3] Destroying Azure resources..."
if [[ -f "$TF_VARS_FILE" ]]; then
  terraform -chdir="$TF_DIR" destroy -auto-approve -var-file="$TF_VARS_FILE"
else
  terraform -chdir="$TF_DIR" destroy -auto-approve
fi

echo ""
echo "[3/3] Removing local cluster and Terraform data..."
if [[ -n "$cluster_name" ]] && command -v kubectl &>/dev/null; then
  kubectl config delete-context "$cluster_name" 2>/dev/null || true
  kubectl config delete-cluster "$cluster_name" 2>/dev/null || true
fi
rm -rf "$TF_DIR/.terraform" "$TF_DIR/.terraform.lock.hcl" "$TF_DIR/tfplan"
find "$TF_DIR" -maxdepth 1 -type f \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.*' \) -delete

echo ""
echo "Cleanup complete."