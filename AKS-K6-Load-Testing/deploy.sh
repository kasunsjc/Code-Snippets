#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

for tool in terraform az kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$tool" >&2; exit 1; }
done

export TF_VAR_subscription_id="${TF_VAR_subscription_id:-$(az account show --query id -o tsv)}"
az account show --subscription "$TF_VAR_subscription_id" --output none

terraform -chdir="$TERRAFORM_DIR" init -input=false
terraform -chdir="$TERRAFORM_DIR" validate
terraform -chdir="$TERRAFORM_DIR" apply "$@"

RESOURCE_GROUP="$(terraform -chdir="$TERRAFORM_DIR" output -raw resource_group_name)"
CLUSTER_NAME="$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name)"
SUBSCRIPTION_ID="$(terraform -chdir="$TERRAFORM_DIR" output -raw subscription_id)"

az aks get-credentials --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
  --context "$CLUSTER_NAME" --overwrite-existing

kubectl --context "$CLUSTER_NAME" create namespace k6-demo --dry-run=client -o yaml | \
  kubectl --context "$CLUSTER_NAME" apply -f -
kubectl --context "$CLUSTER_NAME" apply -f "$SCRIPT_DIR/k8s/target-app.yaml"
kubectl --context "$CLUSTER_NAME" rollout status deployment/target-app -n k6-demo --timeout=300s
kubectl --context "$CLUSTER_NAME" get service target-app -n k6-demo

printf '\nDeployment complete. Wait for the service EXTERNAL-IP, then run the k6 test from the README.\n'