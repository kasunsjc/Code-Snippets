#!/usr/bin/env bash
#
# Removes the policy assignments, the custom policy definition, and destroys
# the Terraform-managed AKS infrastructure created by deploy.sh.

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

if az account show >/dev/null 2>&1 && [[ -d terraform/.terraform ]]; then
  RESOURCE_GROUP=$(terraform -chdir=terraform output -raw resource_group_name 2>/dev/null || true)
  if [[ -n "${RESOURCE_GROUP:-}" ]]; then
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

    echo -e "${GREEN}== Removing built-in policy assignments ==${NC}"
    jq -r '.[].assignmentName' policies/builtin/manifest.json | while read -r NAME; do
      echo -e "${YELLOW}  -> ${NAME}${NC}"
      az policy assignment delete --name "$NAME" --scope "$SCOPE" --only-show-errors 2>/dev/null || true
    done

    echo -e "${GREEN}== Removing custom policy assignment and definition ==${NC}"
    az policy assignment delete --name "require-team-labels" --scope "$SCOPE" --only-show-errors 2>/dev/null || true
    az policy definition delete --name "require-team-labels" --only-show-errors 2>/dev/null || true
  fi
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
