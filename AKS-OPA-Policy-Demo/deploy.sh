#!/usr/bin/env bash
#
# Deploys an AKS cluster with the Azure Policy add-on (Gatekeeper/OPA) enabled,
# then creates and assigns a set of fully custom, OPA/Rego-backed Azure Policy
# definitions (policies/custom/*.definition.json) - each one is a complete
# Microsoft.Authorization/policyDefinitions JSON body demonstrating how to
# author your own Kubernetes policy with Azure Policy for Kubernetes.
#
# Usage:
#   ./deploy.sh            # assigns all policies with effect=audit (non-blocking)
#   EFFECT=deny ./deploy.sh  # assigns all policies with effect=deny (blocking)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

EFFECT="${EFFECT:-audit}"
if [[ "$EFFECT" != "audit" && "$EFFECT" != "deny" ]]; then
  echo -e "${RED}EFFECT must be 'audit' or 'deny' (got '$EFFECT')${NC}"
  exit 1
fi

echo -e "${GREEN}== Checking prerequisites ==${NC}"
for cmd in terraform az kubectl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}Required command '$cmd' not found in PATH.${NC}"
    exit 1
  fi
done

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}Not logged in to Azure CLI. Run 'az login' first.${NC}"
  exit 1
fi

echo -e "${GREEN}== Registering Microsoft.PolicyInsights provider (idempotent) ==${NC}"
az provider register --namespace Microsoft.PolicyInsights >/dev/null

echo -e "${GREEN}== Deploying AKS cluster with Azure Policy add-on via Terraform ==${NC}"
pushd terraform >/dev/null
terraform init -input=false
terraform apply -auto-approve -input=false
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw cluster_name)
LOCATION=$(terraform output -raw location)
popd >/dev/null

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

echo -e "${GREEN}== Fetching AKS credentials ==${NC}"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo -e "${GREEN}== Verifying Azure Policy add-on (azure-policy + gatekeeper pods) ==${NC}"
kubectl get pods -n kube-system -l app=azure-policy || true
kubectl get pods -n gatekeeper-system || true

echo -e "${GREEN}== Creating and assigning custom OPA/Rego policy definitions (effect=${EFFECT}) ==${NC}"
for DEFN_FILE in policies/custom/*.definition.json; do
  NAME=$(basename "$DEFN_FILE" .definition.json)
  PARAM_FILE="policies/custom/${NAME}.parameters.json"

  RULES=$(jq -c '.properties.policyRule' "$DEFN_FILE")
  PARAMS_SCHEMA=$(jq -c '.properties.parameters' "$DEFN_FILE")
  DISPLAY_NAME=$(jq -r '.properties.displayName' "$DEFN_FILE")
  DESCRIPTION=$(jq -r '.properties.description' "$DEFN_FILE")

  echo -e "${YELLOW}  -> ${DISPLAY_NAME}${NC}"

  az policy definition create \
    --name "$NAME" \
    --display-name "$DISPLAY_NAME" \
    --description "$DESCRIPTION" \
    --mode "Microsoft.Kubernetes.Data" \
    --rules "$RULES" \
    --params "$PARAMS_SCHEMA" \
    --metadata category=Kubernetes version=1.0.0 \
    --only-show-errors >/dev/null

  ASSIGN_PARAMS=$(jq --arg effect "$EFFECT" '.effect.value = $effect' "$PARAM_FILE")
  az policy assignment create \
    --name "$NAME" \
    --display-name "$DISPLAY_NAME" \
    --policy "$NAME" \
    --scope "$SCOPE" \
    --params "$ASSIGN_PARAMS" \
    --only-show-errors >/dev/null
done

echo ""
echo -e "${GREEN}== Done ==${NC}"
echo "Resource group : $RESOURCE_GROUP"
echo "Cluster        : $CLUSTER_NAME"
echo "Effect         : $EFFECT"
echo ""
echo -e "${YELLOW}The Azure Policy add-on checks in with the Azure Policy service every ~15 minutes.${NC}"
echo -e "${YELLOW}Allow up to 15 minutes for the Gatekeeper ConstraintTemplates/Constraints to sync before testing.${NC}"
echo ""
echo "Once synced, run: ./scripts/test-policies.sh"
echo "To re-run with blocking (deny) enforcement: EFFECT=deny ./deploy.sh"
