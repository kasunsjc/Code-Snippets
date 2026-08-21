#!/bin/bash
set -euo pipefail

# ============================================================
# Destroy all resources created by the ACNS demo
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}WARNING:${NC} This will destroy all resources created by this demo."
read -r -p "Continue? (y/N) " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

CLUSTER_NAME=$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || echo "")

echo -e "${GREEN}==>${NC} Destroying infrastructure with Terraform..."
terraform -chdir="$TF_DIR" destroy -auto-approve

if [ -n "$CLUSTER_NAME" ] && command -v kubectl &> /dev/null; then
    echo -e "${GREEN}==>${NC} Removing kubeconfig context..."
    kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
fi

echo -e "${GREEN}==>${NC} Removing local Terraform state and provider files..."
find "$TF_DIR" -maxdepth 1 -type f \( -name '*.tfstate' -o -name '*.tfstate.*' \) -delete
rm -rf "$TF_DIR/.terraform"

echo -e "${GREEN}==>${NC} Cleanup complete!"
