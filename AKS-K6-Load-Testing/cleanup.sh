#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() { printf "${GREEN}==>${NC} %s\n" "$1"; }
print_error() { printf "${RED}ERROR:${NC} %s\n" "$1" >&2; }
print_warning() { printf "${YELLOW}WARNING:${NC} %s\n" "$1"; }

check_prerequisites() {
  print_message "Checking prerequisites..."

  for tool in terraform az; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      print_error "$tool is not installed. Please install it first."
      exit 1
    fi
  done

  if ! az account show --output none; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
  fi

  TF_VAR_subscription_id="${TF_VAR_subscription_id:-$(az account show --query id -o tsv)}"
  export TF_VAR_subscription_id
  az account show --subscription "$TF_VAR_subscription_id" --output none
}

terraform_destroy() {
  terraform -chdir="$TF_DIR" init -input=false

  RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
  NODE_RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw node_resource_group_name)"
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
  SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"
  DNS_ZONE_NAME="$(terraform -chdir="$TF_DIR" output -raw dns_zone_name)"
  DNS_ZONE_RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw dns_zone_resource_group)"
  DNS_RECORD_NAME="$(terraform -chdir="$TF_DIR" output -raw dns_record_name)"

  print_warning "This will destroy cluster $CLUSTER_NAME, all its workloads, and resource groups $RESOURCE_GROUP and $NODE_RESOURCE_GROUP."
  print_warning "Managed Prometheus, Grafana, the ingress IP, and $DNS_RECORD_NAME.$DNS_ZONE_NAME will also be removed. The DNS zone itself is retained."
  read -r -p "Continue? (y/N) " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_message "Aborted."
    exit 0
  fi

  print_message "Destroying infrastructure with Terraform..."
  terraform -chdir="$TF_DIR" destroy -auto-approve "$@"
}

verify_cleanup() {
  print_message "Verifying Azure resource cleanup..."

  if [[ -n "$(terraform -chdir="$TF_DIR" state list)" ]]; then
    print_error "Terraform state is not empty. Keeping local state for recovery."
    exit 1
  fi

  for resource_group in "$RESOURCE_GROUP" "$NODE_RESOURCE_GROUP"; do
    if [[ "$(az group exists --subscription "$SUBSCRIPTION_ID" --name "$resource_group")" != "false" ]]; then
      print_error "Resource group $resource_group still exists. Keeping local state; verify Azure cleanup."
      exit 1
    fi
  done

  local remaining_records
  remaining_records="$(az network dns record-set a list --subscription "$SUBSCRIPTION_ID" \
    --resource-group "$DNS_ZONE_RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" \
    --query "[?name=='$DNS_RECORD_NAME'] | length(@)" -o tsv)"
  if [[ "$remaining_records" != "0" ]]; then
    print_error "The demo DNS record still exists. Keeping local state; verify Azure cleanup."
    exit 1
  fi
}

cleanup_local_files() {
  if command -v kubectl >/dev/null 2>&1; then
    print_message "Removing kubeconfig context..."
    kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
  else
    print_warning "kubectl not found; skipping local kubeconfig cleanup."
  fi

  print_message "Removing local Terraform state and provider files..."
  find "$TF_DIR" -maxdepth 1 -type f \( -name '*.tfstate' -o -name '*.tfstate.*' \) -delete
  rm -rf "$TF_DIR/.terraform"
  print_message "Cleanup complete!"
}

check_prerequisites
terraform_destroy "$@"
verify_cleanup
cleanup_local_files