#!/bin/bash
# ==============================================================================
# AKS Control Plane Metrics demo - cleanup
# ------------------------------------------------------------------------------
# Destroys all Azure resources created by deploy.sh and removes local
# Terraform state, provider folders and the kubectl context.
#
# Usage:
#   ./cleanup.sh        # asks for confirmation
#   ./cleanup.sh -y     # no confirmation
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

AUTO_APPROVE=false
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
  AUTO_APPROVE=true
fi

if ! command -v terraform >/dev/null 2>&1; then
  print_error "terraform is not installed."
  exit 1
fi

RESOURCE_GROUP=""
CLUSTER_NAME=""
if [[ -f "$TF_DIR/terraform.tfstate" ]]; then
  RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name 2>/dev/null || echo "")"
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || echo "")"
fi

if [[ "$AUTO_APPROVE" != "true" ]]; then
  print_warning "This will DESTROY all resources for the AKS control plane metrics demo${RESOURCE_GROUP:+ in '$RESOURCE_GROUP'}."
  read -r -p "Are you sure? (yes/no): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    print_message "Cleanup cancelled."
    exit 0
  fi
fi

if [[ -f "$TF_DIR/terraform.tfstate" ]]; then
  print_message "Destroying Terraform-managed resources..."
  terraform -chdir="$TF_DIR" init -input=false >/dev/null
  terraform -chdir="$TF_DIR" destroy -auto-approve -input=false
else
  print_warning "No Terraform state found. Skipping terraform destroy."
fi

# Make sure nothing was left behind (e.g. if state was lost)
if [[ -n "$RESOURCE_GROUP" ]] && command -v az >/dev/null 2>&1; then
  if [[ "$(az group exists --name "$RESOURCE_GROUP")" == "true" ]]; then
    print_warning "Resource group $RESOURCE_GROUP still exists. Deleting..."
    az group delete --name "$RESOURCE_GROUP" --yes
  fi
fi

if [[ -n "$CLUSTER_NAME" ]] && command -v kubectl >/dev/null 2>&1; then
  print_message "Removing kubectl context $CLUSTER_NAME..."
  kubectl config delete-context "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kubectl config delete-cluster "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kubectl config unset "users.clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" >/dev/null 2>&1 || true
fi

print_message "Removing local Terraform state and provider folder..."
rm -rf "$TF_DIR/.terraform"
rm -f "$TF_DIR/.terraform.lock.hcl" "$TF_DIR"/terraform.tfstate* "$TF_DIR"/*.tfplan

print_message "Cleanup complete."
