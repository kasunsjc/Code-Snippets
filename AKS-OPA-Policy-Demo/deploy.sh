#!/usr/bin/env bash
#
# Deploys an AKS cluster with the Azure Policy add-on (Gatekeeper/OPA) enabled,
# then assigns a curated set of built-in Kubernetes policies plus one custom
# OPA/Rego-backed policy definition.
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

echo -e "${GREEN}== Assigning built-in Kubernetes policies (effect=${EFFECT}) ==${NC}"
jq -c '.[]' policies/builtin/manifest.json | while read -r item; do
  NAME=$(echo "$item" | jq -r '.assignmentName')
  DISPLAY=$(echo "$item" | jq -r '.displayName')
  DEFID=$(echo "$item" | jq -r '.policyDefinitionId')
  PFILE=$(echo "$item" | jq -r '.parameterFile')
  PARAMS=$(jq --arg effect "$EFFECT" '.effect.value = $effect' "policies/builtin/$PFILE")

  echo -e "${YELLOW}  -> ${DISPLAY}${NC}"
  az policy assignment create \
    --name "$NAME" \
    --display-name "$DISPLAY" \
    --policy "$DEFID" \
    --scope "$SCOPE" \
    --params "$PARAMS" \
    --only-show-errors >/dev/null
done

echo -e "${GREEN}== Creating custom OPA/Rego policy definition (require-team-labels) ==${NC}"
DEFN_FILE="policies/custom/require-team-labels.definition.json"
RULES=$(jq -c '.properties.policyRule' "$DEFN_FILE")
PARAMS_SCHEMA=$(jq -c '.properties.parameters' "$DEFN_FILE")
DISPLAY_NAME=$(jq -r '.properties.displayName' "$DEFN_FILE")
DESCRIPTION=$(jq -r '.properties.description' "$DEFN_FILE")

az policy definition create \
  --name "require-team-labels" \
  --display-name "$DISPLAY_NAME" \
  --description "$DESCRIPTION" \
  --mode "Microsoft.Kubernetes.Data" \
  --rules "$RULES" \
  --params "$PARAMS_SCHEMA" \
  --metadata category=Kubernetes version=1.0.0 \
  --only-show-errors >/dev/null

echo -e "${GREEN}== Assigning custom policy (effect=${EFFECT}) ==${NC}"
CUSTOM_PARAMS=$(jq --arg effect "$EFFECT" '.effect.value = $effect' policies/custom/require-team-labels.parameters.json)
az policy assignment create \
  --name "require-team-labels" \
  --display-name "Require team/environment labels (custom OPA policy)" \
  --policy "require-team-labels" \
  --scope "$SCOPE" \
  --params "$CUSTOM_PARAMS" \
  --only-show-errors >/dev/null

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
