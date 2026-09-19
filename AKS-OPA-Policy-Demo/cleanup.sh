#!/usr/bin/env bash
#
# Removes the Azure policy assignments and definitions, and destroys the
# Terraform-managed AKS infrastructure. Local policy JSON/YAML files remain.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

read -r -p "This will destroy the AKS cluster and remove all demo policy assignments. Continue? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

if az account show >/dev/null 2>&1; then
  RESOURCE_GROUP=$(terraform -chdir=terraform output -raw resource_group_name 2>/dev/null || true)
  RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-opa-policy-demo}"
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

  echo -e "${GREEN}== Removing all policy assignments at the demo resource-group scope ==${NC}"
  az policy assignment list \
    --scope "$SCOPE" \
    --query '[].name' \
    --output tsv \
    --only-show-errors 2>/dev/null | while read -r ASSIGNMENT_NAME; do
      [[ -z "$ASSIGNMENT_NAME" ]] && continue
      echo -e "${YELLOW}  -> assignment: ${ASSIGNMENT_NAME}${NC}"
      az policy assignment delete \
        --name "$ASSIGNMENT_NAME" \
        --scope "$SCOPE" \
        --only-show-errors 2>/dev/null || true
    done

  echo -e "${GREEN}== Removing custom policy definitions from Azure only ==${NC}"
  # DEFN_FILE is used only to derive the Azure definition name; the file is never deleted.
  for DEFN_FILE in policies/custom/*.definition.json; do
    NAME=$(basename "$DEFN_FILE" .definition.json)
    echo -e "${YELLOW}  -> definition: ${NAME}${NC}"
    az policy definition delete --name "$NAME" --only-show-errors 2>/dev/null || true
  done
else
  echo -e "${YELLOW}Azure CLI is not logged in; skipping policy assignment and definition cleanup.${NC}"
fi

echo -e "${GREEN}== Destroying Terraform infrastructure ==${NC}"
pushd terraform >/dev/null
if [[ -d .terraform ]]; then
  terraform destroy -auto-approve -input=false
fi
setopt nocorrect 2>/dev/null || true
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
popd >/dev/null

echo -e "${GREEN}Cleanup complete.${NC}"
