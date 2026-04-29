#!/bin/bash
set -euo pipefail

# ============================================================
# Deploy Falco + Microsoft Sentinel demo on AKS
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
DEPLOYMENT_NAME="falco-sentinel-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_prereqs() {
  log "Checking prerequisites..."
  for tool in az kubectl helm jq; do
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
}

get_webhook_url() {
  log "Fetching Logic App callback URL..."
  WEBHOOK_URL=$(az rest --method post --uri "$(az resource show \
    -g "$RESOURCE_GROUP" -n "$LOGIC_APP_NAME" \
    --resource-type Microsoft.Logic/workflows \
    --query id -o tsv)/triggers/manual/listCallbackUrl?api-version=2019-05-01" \
    --query value -o tsv)
  if [[ -z "$WEBHOOK_URL" ]]; then
    err "Could not retrieve webhook URL"; exit 1
  fi
  log "Webhook URL acquired."
}

get_aks_credentials() {
  log "Getting AKS credentials..."
  az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKS_NAME" --overwrite-existing
  kubectl config use-context "$AKS_NAME"
}

install_falco() {
  log "Adding Falco Helm repo..."
  helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null
  helm repo update >/dev/null

  log "Rendering Falco values with webhook URL..."
  TMP_VALUES=$(mktemp)
  # Escape & in URL for sed
  ESCAPED_URL=$(printf '%s\n' "$WEBHOOK_URL" | sed 's/[&/\]/\\&/g')
  sed "s|__WEBHOOK_URL__|$ESCAPED_URL|g" "$SCRIPT_DIR/falco-values.yaml.tpl" > "$TMP_VALUES"

  log "Installing Falco + falcosidekick into namespace 'falco'..."
  helm upgrade --install falco falcosecurity/falco \
    --namespace falco --create-namespace \
    --values "$TMP_VALUES" \
    --wait --timeout 8m

  rm -f "$TMP_VALUES"
  log "Falco deployed."
}

verify() {
  log "Falco pods:"
  kubectl get pods -n falco
  echo ""
  log "Falcosidekick service:"
  kubectl get svc -n falco | grep falcosidekick || true
}

print_summary() {
  cat <<EOF

==========================================
  Falco → Sentinel demo: ready
==========================================
  Resource Group:       $RESOURCE_GROUP
  AKS Cluster:          $AKS_NAME
  Log Analytics:        $WORKSPACE_NAME
  Custom Log Table:     FalcoAlerts_CL  (created on first event, ~5 min latency)
  Logic App:            $LOGIC_APP_NAME

==========================================
  Run the demo
==========================================
  # 1) Trigger Falco events
  kubectl apply -f $SCRIPT_DIR/sample-attacks/attack-pod.yaml
  $SCRIPT_DIR/sample-attacks/trigger-events.sh

  # 2) Watch Falco detect them in real-time
  kubectl logs -n falco -l app.kubernetes.io/name=falco -f

  # 3) (Optional) Open falcosidekick UI
  kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802

  # 4) Verify ingestion in Log Analytics (wait 2-10 min for first event)
  az monitor log-analytics query \\
    -w \$(az monitor log-analytics workspace show \\
            -g $RESOURCE_GROUP -n $WORKSPACE_NAME --query customerId -o tsv) \\
    --analytics-query "FalcoAlerts_CL | take 20" -o table

  # 5) Open Microsoft Sentinel → Incidents
  echo "https://portal.azure.com/#view/Microsoft_Azure_Security_Insights/MainMenuBlade/~/Incidents"

EOF
}

main() {
  check_prereqs
  create_rg
  deploy_bicep
  get_outputs
  get_webhook_url
  get_aks_credentials
  install_falco
  verify
  print_summary
}

main "$@"
