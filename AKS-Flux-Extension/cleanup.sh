#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

for tool in az terraform jq; do
  command -v "$tool" >/dev/null || { printf 'Missing prerequisite: %s\n' "$tool" >&2; exit 1; }
done
az account show --output none
: "${ARM_SUBSCRIPTION_ID:?Export ARM_SUBSCRIPTION_ID for the deployment subscription first.}"
if [[ "$(az account show --query id --output tsv)" != "$ARM_SUBSCRIPTION_ID" ]]; then
  printf 'ARM_SUBSCRIPTION_ID must match the active Azure CLI subscription.\n' >&2
  exit 1
fi

printf 'This destroys the demo AKS cluster, Flux configuration, extension and resource groups.\n'
read -r -p 'Type destroy to continue: ' confirmation
[[ "$confirmation" == "destroy" ]] || { printf 'Cancelled.\n'; exit 0; }

terraform -chdir="$TF_DIR" init -input=false
OUTPUTS="$(terraform -chdir="$TF_DIR" output -json)"
RESOURCE_GROUP="$(jq -r '.resource_group_name.value // empty' <<< "$OUTPUTS")"
NODE_RESOURCE_GROUP="$(jq -r '.node_resource_group_name.value // empty' <<< "$OUTPUTS")"
terraform -chdir="$TF_DIR" destroy "$@"

for group in "$RESOURCE_GROUP" "$NODE_RESOURCE_GROUP"; do
  if [[ -n "$group" ]] && [[ "$(az group exists --name "$group" --output tsv)" != "false" ]]; then
    printf 'Resource group %s still exists. Retaining state; investigate before removing it.\n' "$group" >&2
    exit 1
  fi
done

rm -rf "${TF_DIR}/.terraform"
rm -f "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup" "${SCRIPT_DIR}/kubeconfig"
printf 'Terraform destroy completed; local state, provider cache and demo kubeconfig removed.\n'