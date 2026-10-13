#!/bin/bash
# ==============================================================================
# AKS Control Plane Metrics demo - cleanup
# ------------------------------------------------------------------------------
# Destroys all Azure resources created by deploy.sh and removes local
# Terraform state, provider folders and the kubectl context.
#
# Usage:
#   ./cleanup.sh                     # asks for confirmation
#   ./cleanup.sh -y                  # no confirmation
#   ./cleanup.sh -g <resource-group> # resource group to delete if state is lost
#
# If no Terraform state exists, the resource group is taken from -g, the
# RESOURCE_GROUP environment variable, or derived from PROJECT/ENVIRONMENT
# (defaults: cpmetrics/demo -> rg-cpmetrics-demo).
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
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes)
      AUTO_APPROVE=true
      shift
      ;;
    -g | --resource-group)
      RESOURCE_GROUP="${2:-}"
      shift 2
      ;;
    *)
      print_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if ! command -v terraform >/dev/null 2>&1; then
  print_error "terraform is not installed."
  exit 1
fi

HAS_STATE=false
CLUSTER_NAME=""
if [[ -f "$TF_DIR/terraform.tfstate" ]]; then
  HAS_STATE=true
  STATE_RG="$(terraform -chdir="$TF_DIR" output -raw resource_group_name 2>/dev/null || echo "")"
  RESOURCE_GROUP="${RESOURCE_GROUP:-$STATE_RG}"
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || echo "")"
fi

# Fall back to the naming convention used in terraform/main.tf
if [[ -z "$RESOURCE_GROUP" ]]; then
  RESOURCE_GROUP="rg-${PROJECT:-cpmetrics}-${ENVIRONMENT:-demo}"
  print_warning "Resource group not found in state; using '$RESOURCE_GROUP' (override with -g)."
fi
CLUSTER_NAME="${CLUSTER_NAME:-aks-${RESOURCE_GROUP#rg-}}"

if [[ "$AUTO_APPROVE" != "true" ]]; then
  print_warning "This will DESTROY all resources for the AKS control plane metrics demo in '$RESOURCE_GROUP'."
  read -r -p "Are you sure? (yes/no): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    print_message "Cleanup cancelled."
    exit 0
  fi
fi

DESTROY_OK=false
if [[ "$HAS_STATE" == "true" ]]; then
  print_message "Destroying Terraform-managed resources..."
  if terraform -chdir="$TF_DIR" init -input=false >/dev/null &&
    terraform -chdir="$TF_DIR" destroy -auto-approve -input=false; then
    DESTROY_OK=true
  else
    print_warning "terraform destroy failed. Trying resource group deletion as a fallback..."
  fi
else
  print_warning "No Terraform state found. Skipping terraform destroy."
fi

# Delete anything left behind (state lost or partial destroy)
RG_GONE=false
if command -v az >/dev/null 2>&1; then
  if ! RG_EXISTS="$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null)"; then
    print_warning "Could not query resource group $RESOURCE_GROUP (check 'az login')."
  elif [[ "$RG_EXISTS" == "true" ]]; then
    print_warning "Resource group $RESOURCE_GROUP still exists. Deleting..."
    if az group delete --name "$RESOURCE_GROUP" --yes; then
      RG_GONE=true
    fi
  elif [[ "$RG_EXISTS" == "false" ]]; then
    RG_GONE=true
  else
    print_warning "Unexpected response from 'az group exists': '$RG_EXISTS'"
  fi
else
  print_warning "Azure CLI not found; cannot verify that '$RESOURCE_GROUP' was removed."
fi

if [[ "$DESTROY_OK" != "true" && "$RG_GONE" != "true" ]]; then
  print_error "Could not confirm that Azure resources were deleted."
  print_error "Terraform state was kept in $TF_DIR so you can retry ./cleanup.sh."
  exit 1
fi

if command -v kubectl >/dev/null 2>&1; then
  print_message "Removing kubectl context $CLUSTER_NAME..."
  kubectl config delete-context "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kubectl config delete-cluster "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kubectl config unset "users.clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" >/dev/null 2>&1 || true
fi

print_message "Removing local Terraform state and provider folder..."
rm -rf "$TF_DIR/.terraform"
rm -f "$TF_DIR/.terraform.lock.hcl" "$TF_DIR"/terraform.tfstate* "$TF_DIR"/*.tfplan

print_message "Cleanup complete."
