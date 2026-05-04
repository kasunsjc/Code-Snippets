#!/bin/bash
set -euo pipefail

# ============================================================
# Deploy Falco + Microsoft Sentinel demo on AKS
# Mirrors the kasunsjc/aks-labs Falco workflow
# (https://github.com/kasunsjc/aks-labs/blob/main/.github/workflows/deploy-falco.yml)
# but runs locally and provisions infra via Bicep.
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
err()  { echo -e "${RED}ERROR:${NC} $1"; }

# Configuration (override via env vars)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-falco-sentinel-demo}"
LOCATION="${LOCATION:-northeurope}"
PROJECT_NAME="${PROJECT_NAME:-falcosec}"
CLUSTER_NAME="${CLUSTER_NAME:-${PROJECT_NAME}-aks}"
FALCO_NAMESPACE="${FALCO_NAMESPACE:-falco}"
LOGIC_APP_NAME="${LOGIC_APP_NAME:-logic-falco-webhook}"
DEPLOYMENT_NAME="falco-sentinel-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_prereqs() {
  log "Checking prerequisites..."
  for tool in az kubectl helm jq envsubst; do
    command -v "$tool" >/dev/null 2>&1 || { err "$tool not installed"; exit 1; }
  done
  az account show >/dev/null 2>&1 || { err "Not logged in. Run 'az login'."; exit 1; }
  log "Subscription: $(az account show --query name -o tsv)"
}

create_rg() {
  log "Creating resource group: $RESOURCE_GROUP ($LOCATION)"
  az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
}

deploy_bicep() {
  log "Deploying Bicep ($DEPLOYMENT_NAME) — this takes ~10 minutes..."
  az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$SCRIPT_DIR/main.bicep" \
    --parameters "$SCRIPT_DIR/main.bicepparam" \
    --parameters location="$LOCATION" projectName="$PROJECT_NAME" clusterName="$CLUSTER_NAME" \
    -o none
  log "Bicep deployment complete."
}

get_outputs() {
  log "Reading deployment outputs..."
  OUTPUTS=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" --query properties.outputs -o json)
  WORKSPACE_NAME=$(echo "$OUTPUTS" | jq -r .workspaceName.value)
  LOGIC_APP_NAME=$(echo "$OUTPUTS" | jq -r .logicAppName.value)
  AKS_NAME=$(echo "$OUTPUTS" | jq -r .aksClusterName.value)
  CUSTOM_TABLE=$(echo "$OUTPUTS" | jq -r .customLogTable.value)
  # webhookUrl is emitted directly by main.bicep via listCallbackUrl()
  WEBHOOK_URL=$(echo "$OUTPUTS" | jq -r .webhookUrl.value)
  if [[ -z "$WEBHOOK_URL" || "$WEBHOOK_URL" == "null" ]]; then
    err "webhookUrl output missing from deployment. Check the Logic App deployment."; exit 1
  fi
  log "Webhook URL acquired from deployment output: ${WEBHOOK_URL:0:60}..."
}

get_aks_credentials() {
  log "Getting AKS credentials..."
  az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKS_NAME" --overwrite-existing
}

create_namespace() {
  log "Applying Falco namespace..."
  kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
}

install_falco() {
  log "Adding Falco Helm repo..."
  helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null
  helm repo update >/dev/null

  log "Rendering values.yaml with webhook URL via envsubst..."
  export LOGIC_APP_WEBHOOK_URL="$WEBHOOK_URL"
  TMP_VALUES=$(mktemp)
  envsubst < "$SCRIPT_DIR/values.yaml" > "$TMP_VALUES"

  log "Installing Falco + falcosidekick into namespace '$FALCO_NAMESPACE'..."
  helm upgrade --install falco falcosecurity/falco \
    --namespace "$FALCO_NAMESPACE" \
    --values "$TMP_VALUES" \
    --timeout 10m \
    --wait

  rm -f "$TMP_VALUES"
  log "Falco deployed."
}

verify() {
  log "Waiting for Falco DaemonSet rollout..."
  kubectl rollout status daemonset/falco -n "$FALCO_NAMESPACE" --timeout=300s

  echo ""
  log "Falco pods:"
  kubectl get pods -n "$FALCO_NAMESPACE" -l app.kubernetes.io/name=falco

  echo ""
  log "Falcosidekick pods:"
  kubectl get pods -n "$FALCO_NAMESPACE" -l app.kubernetes.io/name=falcosidekick || true
}

list_sentinel_rules() {
  log "Listing deployed Sentinel analytics rules..."
  az sentinel alert-rule list \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$WORKSPACE_NAME" \
    --query "[?contains(displayName, 'Falco')].{Name:displayName, Enabled:enabled, Severity:severity}" \
    --output table 2>/dev/null \
    || warn "Install the Sentinel CLI extension to list rules: az extension add --name sentinel"
}

enable_sentinel_rules() {
  log "Enabling Sentinel analytics rules via Bicep re-deploy (rulesEnabled=true)..."
  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "falco-enable-rules-$(date +%Y%m%d-%H%M%S)" \
    --template-file "$SCRIPT_DIR/main.bicep" \
    --parameters "$SCRIPT_DIR/main.bicepparam" \
    --parameters rulesEnabled=true \
    --output none
  log "All Sentinel rules enabled."
}

print_summary() {
  cat <<EOF

==========================================
  Falco → Sentinel demo: ready
==========================================
  Resource Group:       $RESOURCE_GROUP
  AKS Cluster:          $AKS_NAME
  Log Analytics:        $WORKSPACE_NAME
  Custom Log Table:     $CUSTOM_TABLE  (created on first event, ~5 min latency)
  Logic App:            $LOGIC_APP_NAME
  Falco Namespace:      $FALCO_NAMESPACE

==========================================
  Run the demo
==========================================
  # 1) Trigger Falco events
  kubectl apply -f $SCRIPT_DIR/sample-attacks/attack-pod.yaml
  $SCRIPT_DIR/sample-attacks/trigger-events.sh

  # 2) Watch Falco detect them in real-time
  kubectl logs -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco -f

  # 3) Watch falcosidekick forward to Logic App
  kubectl logs -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falcosidekick -f

  # 4) Verify ingestion in Log Analytics (wait 2-10 min for first event)
  WS_ID=\$(az monitor log-analytics workspace show \\
            -g $RESOURCE_GROUP -n $WORKSPACE_NAME --query customerId -o tsv)
  az monitor log-analytics query -w "\$WS_ID" \\
    --analytics-query "$CUSTOM_TABLE | take 20" -o table

  # 5) Enable Sentinel analytics rules (disabled at deploy time; table must exist first)
  #    Run this AFTER step 4 confirms data is arriving in Log Analytics:
  $SCRIPT_DIR/deploy.sh --enable-rules   # or run enable_sentinel_rules() directly

  # 6) Open Microsoft Sentinel → Incidents
  echo "https://portal.azure.com/#view/Microsoft_Azure_Security_Insights/MainMenuBlade/~/Incidents"

EOF
}

main() {
  check_prereqs
  create_rg
  deploy_bicep
  get_outputs
  get_aks_credentials
  create_namespace
  install_falco
  verify
  list_sentinel_rules
  print_summary
}

# Support --enable-rules flag to re-enable Sentinel rules after data arrives
if [[ "${1:-}" == "--enable-rules" ]]; then
  enable_sentinel_rules
  exit 0
fi

main "$@"
