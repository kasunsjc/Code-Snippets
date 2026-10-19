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

  for tool in terraform az kubectl; do
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
  print_message "Prerequisites check passed!"
}

terraform_apply() {
  print_message "Provisioning infrastructure with Terraform..."
  print_warning "This may take 10-15 minutes. Terraform changes are automatically approved."

  terraform -chdir="$TF_DIR" init -input=false
  terraform -chdir="$TF_DIR" validate
  terraform -chdir="$TF_DIR" apply -auto-approve "$@"
}

get_credentials() {
  RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
  SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"

  print_message "Fetching AKS credentials..."
  az aks get-credentials --subscription "$SUBSCRIPTION_ID" \
    --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --context "$CLUSTER_NAME" --overwrite-existing
}

deploy_sample_app() {
  print_message "Deploying the sample API..."
  kubectl --context "$CLUSTER_NAME" create namespace k6-demo --dry-run=client -o yaml | \
    kubectl --context "$CLUSTER_NAME" apply -f -
  kubectl --context "$CLUSTER_NAME" apply -f "$SCRIPT_DIR/k8s/target-app.yaml"
  kubectl --context "$CLUSTER_NAME" rollout status deployment/target-app -n k6-demo --timeout=300s
  kubectl --context "$CLUSTER_NAME" get service target-app -n k6-demo
}

show_summary() {
  printf '\n'
  print_message "Deployment complete!"
  printf '\n  Resource group : %s\n  AKS cluster    : %s\n\n' "$RESOURCE_GROUP" "$CLUSTER_NAME"
  printf 'Wait for the service EXTERNAL-IP, then run the k6 test from the README.\n'
}

check_prerequisites
terraform_apply "$@"
get_credentials
deploy_sample_app
show_summary