#!/usr/bin/env bash
# Destroy the demo; remove local state/cache only after both resource groups are confirmed absent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
for tool in terraform az; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
if [[ ! -f "$TF_DIR/terraform.tfstate" ]]; then
  echo "Local state is missing. Recover state before cleanup; do not discard resource ownership." >&2
  exit 1
fi

RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
NODE_RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw node_resource_group_name)"
SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"
# Destroy the demo without an interactive approval prompt.
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" destroy -auto-approve -input=false "$@"

for group in "$RESOURCE_GROUP" "$NODE_RESOURCE_GROUP"; do
  exists="$(az group exists --subscription "$SUBSCRIPTION_ID" --name "$group" --output tsv)"
  if [[ "$exists" != false ]]; then
    echo "Resource group $group still exists. Inspect it; retaining state/cache for recovery." >&2
    exit 1
  fi
done

rm -rf "$TF_DIR/.terraform"
rm -f "$TF_DIR/.terraform.lock.hcl" "$TF_DIR"/terraform.tfstate* "$TF_DIR"/*.tfplan
echo "Both resource groups are gone; local Terraform state and provider cache removed."
