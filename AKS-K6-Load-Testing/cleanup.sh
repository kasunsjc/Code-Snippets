#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

for tool in terraform az; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$tool" >&2; exit 1; }
done

export TF_VAR_subscription_id="${TF_VAR_subscription_id:-$(az account show --query id -o tsv)}"
terraform -chdir="$TERRAFORM_DIR" init -input=false

RESOURCE_GROUP="$(terraform -chdir="$TERRAFORM_DIR" output -raw resource_group_name)"
NODE_RESOURCE_GROUP="$(terraform -chdir="$TERRAFORM_DIR" output -raw node_resource_group_name)"
SUBSCRIPTION_ID="$(terraform -chdir="$TERRAFORM_DIR" output -raw subscription_id)"

printf 'This destroys the demo cluster, all its workloads, and resource groups %s and %s.\n' \
  "$RESOURCE_GROUP" "$NODE_RESOURCE_GROUP"
terraform -chdir="$TERRAFORM_DIR" destroy "$@"

if [[ -n "$(terraform -chdir="$TERRAFORM_DIR" state list)" ]]; then
  printf 'Terraform state is not empty. Keeping local state for recovery.\n' >&2
  exit 1
fi

for resource_group in "$RESOURCE_GROUP" "$NODE_RESOURCE_GROUP"; do
  if [[ "$(az group exists --subscription "$SUBSCRIPTION_ID" --name "$resource_group")" != "false" ]]; then
    printf 'Resource group %s still exists. Keeping local state; verify Azure cleanup.\n' "$resource_group" >&2
    exit 1
  fi
done

rm -rf "$TERRAFORM_DIR/.terraform"
rm -f "$TERRAFORM_DIR/terraform.tfstate" "$TERRAFORM_DIR/terraform.tfstate.backup"
printf 'Azure resources removed; local Terraform state and provider cache removed.\n'