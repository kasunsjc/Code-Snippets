#!/bin/bash
# Tears down the Harbor demo: Helm releases, the DNS record this demo created
# (never the shared zone itself), then all Terraform-managed Azure resources.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

read -r -p "This will destroy the Harbor demo cluster and all its Azure resources. Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

if [[ ! -d "$TF_DIR/.terraform" ]]; then
  error "No Terraform state found in $TF_DIR - nothing to clean up."
  exit 1
fi

DNS_ZONE_NAME="$(terraform -chdir="$TF_DIR" output -raw dns_zone_name 2>/dev/null || true)"
DNS_ZONE_RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw dns_zone_resource_group 2>/dev/null || true)"
HARBOR_SUBDOMAIN="$(terraform -chdir="$TF_DIR" output -raw harbor_subdomain 2>/dev/null || true)"

if [[ -n "$DNS_ZONE_NAME" && -n "$HARBOR_SUBDOMAIN" ]]; then
  info "Removing Azure DNS record $HARBOR_SUBDOMAIN.$DNS_ZONE_NAME (zone itself is left untouched)..."
  az network dns record-set a delete \
    --resource-group "$DNS_ZONE_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE_NAME" \
    --name "$HARBOR_SUBDOMAIN" \
    --yes &>/dev/null || true
fi

if kubectl config get-contexts &>/dev/null; then
  info "Uninstalling Helm releases (best-effort)..."
  helm uninstall harbor -n harbor &>/dev/null || true
  helm uninstall cert-manager -n cert-manager &>/dev/null || true
  helm uninstall traefik -n traefik &>/dev/null || true
  kubectl delete namespace harbor cert-manager traefik --ignore-not-found &>/dev/null || true
fi

info "Running terraform destroy..."
terraform -chdir="$TF_DIR" destroy -auto-approve

info "Removing local Terraform state and provider files..."
find "$TF_DIR" -maxdepth 1 -type f \( -name '*.tfstate' -o -name '*.tfstate.*' \) -delete
rm -rf "$TF_DIR/.terraform" "$TF_DIR/.terraform.lock.hcl"
rm -rf "$SCRIPT_DIR/.rendered"

info "Cleanup complete."
