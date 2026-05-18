#!/bin/bash
# ============================================================
# Deployment Script for Falco AKS + Microsoft Sentinel demo
# ============================================================
# Usage:
#   ./deploy.sh                 # full deploy (infra → Falco → wait → rules)
#   ./deploy.sh --enable-rules  # only (re)create Sentinel analytics rules
#   ./deploy.sh --skip-rules    # deploy infra + Falco only
#   ./deploy.sh --no-wait       # skip the wait-for-FalcoLogs_CL gate
#
# The Logic App callback URL contains a SAS signature and is treated as a
# secret: it is fetched at runtime via `az logic workflow show-callback-url`
# and never echoed to stdout. It is also no longer surfaced as a Bicep output.
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colours / logging
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------------------------------------------------------------------------
# Defaults / globals
# ---------------------------------------------------------------------------
LOCATION="eastus"
SUBSCRIPTION_ID=""
DEPLOYMENT_NAME="main-subscription"

# Random 6-character alphanumeric suffix to ensure unique resource names.
# Generated once per script run so all resources share the same suffix.
# Uses openssl to avoid SIGPIPE issues from /dev/urandom pipelines under pipefail.
RANDOM_SUFFIX=""

# Defaults for --enable-rules-only mode (overridden from deployment outputs)
RESOURCE_GROUP=""
AKS_NAME=""
LAW_NAME=""
WORKSPACE_ID=""
LOGIC_APP_NAME=""
LOGIC_APP_TRIGGER=""

MODE="full"            # full | enable-rules-only | skip-rules
WAIT_FOR_LOGS=true     # gate Sentinel rule creation on FalcoLogs_CL having data
WAIT_TIMEOUT_MIN=20    # max minutes to wait for first FalcoLogs_CL row

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --enable-rules) MODE="enable-rules-only"; shift ;;
        --skip-rules)   MODE="skip-rules"; shift ;;
        --no-wait)      WAIT_FOR_LOGS=false; shift ;;
        --wait-timeout) WAIT_TIMEOUT_MIN="$2"; shift 2 ;;
        -h|--help)
            sed -n '/^# Usage:/,/^# ====/p' "$0" | head -n -1 | sed 's/^# \{0,2\}//'
            exit 0 ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Prerequisite checks (jq is REQUIRED — both rules + workbook need it)
# ---------------------------------------------------------------------------
check_prerequisites() {
    print_info "Checking prerequisites..."

    local missing=()
    for cmd in az kubectl helm jq uuidgen openssl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ! command -v sha1sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        missing+=("sha1sum (or shasum)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing[*]}"
        print_error "Install them and re-run. Hints:"
        print_error "  az      → https://docs.microsoft.com/cli/azure/install-azure-cli"
        print_error "  kubectl → https://kubernetes.io/docs/tasks/tools/"
        print_error "  helm    → https://helm.sh/docs/intro/install/"
        print_error "  jq      → 'brew install jq' (macOS) or 'apt-get install jq' (Linux)"
        exit 1
    fi

    print_info "All prerequisites are met!"
}

login_azure() {
    print_info "Checking Azure login status..."
    if ! az account show &>/dev/null; then
        print_info "Not logged in to Azure. Logging in..."
        az login
    fi
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    print_info "Using subscription: $SUBSCRIPTION_ID"
}

# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------
deploy_infrastructure() {
    print_info "Deploying Azure infrastructure with Bicep (subscription scope)..."
    print_info "Resource name suffix: ${RANDOM_SUFFIX}"

    print_info "Resolving current user object ID for AKS RBAC assignment..."
    local user_id
    user_id=$(az ad signed-in-user show --query id -o tsv)

    az deployment sub create \
        --location "$LOCATION" \
        --name "$DEPLOYMENT_NAME" \
        --template-file "$SCRIPT_DIR/../main-subscription.bicep" \
        --parameters "$SCRIPT_DIR/../main-subscription.bicepparam" \
        --parameters aksAdminPrincipalId="$user_id" \
        --parameters resourceGroupName="rg-falco-demo-${RANDOM_SUFFIX}" \
        --parameters aksClusterName="aks-falco-demo-${RANDOM_SUFFIX}" \
        --parameters logAnalyticsWorkspaceName="law-falco-demo-${RANDOM_SUFFIX}" \
        --output table

    print_info "Infrastructure deployed successfully!"
}

get_deployment_outputs() {
    print_info "Retrieving deployment outputs..."

    local outputs
    outputs=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json)

    RESOURCE_GROUP=$(echo "$outputs"     | jq -r '.resourceGroupName.value')
    AKS_NAME=$(echo "$outputs"           | jq -r '.aksClusterName.value')
    LAW_NAME=$(echo "$outputs"           | jq -r '.logAnalyticsWorkspaceName.value')
    WORKSPACE_ID=$(echo "$outputs"       | jq -r '.workspaceCustomerId.value')
    LOGIC_APP_NAME=$(echo "$outputs"     | jq -r '.logicAppName.value')
    LOGIC_APP_TRIGGER=$(echo "$outputs"  | jq -r '.logicAppTriggerName.value')

    print_info "Resource Group: $RESOURCE_GROUP"
    print_info "AKS Cluster:    $AKS_NAME"
    print_info "Log Analytics:  $LAW_NAME (customerId=$WORKSPACE_ID)"
    print_info "Logic App:      $LOGIC_APP_NAME"
}

# Fetches the Logic App callback URL at runtime. The value is treated as a
# secret and is NEVER echoed to stdout (it carries an HMAC signature that
# grants invocation rights). It is consumed only by `helm --set`.
fetch_webhook_url_silently() {
    print_info "Fetching Logic App callback URL (value will not be printed)..."
    WEBHOOK_URL=$(az rest --method post \
        --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/triggers/${LOGIC_APP_TRIGGER}/listCallbackUrl?api-version=2017-07-01" \
        --query value -o tsv)

    if [[ -z "$WEBHOOK_URL" || "$WEBHOOK_URL" == "null" ]]; then
        print_error "Could not retrieve Logic App callback URL."
        exit 1
    fi
    print_info "Webhook URL retrieved (redacted)."
}

# ---------------------------------------------------------------------------
# Falco / kubectl
# ---------------------------------------------------------------------------
configure_kubectl() {
    print_info "Configuring kubectl..."
    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AKS_NAME" \
        --overwrite-existing
    kubectl cluster-info
}

install_falco() {
    print_info "Installing Falco on AKS cluster..."

    helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null
    helm repo update >/dev/null

    kubectl apply -f "$SCRIPT_DIR/../k8s/falco-namespace.yaml"

    # The webhook URL is passed via --set (single arg, not echoed by helm in
    # default verbosity). Avoid `--set-string` printing in CI-debug mode.
    helm upgrade --install falco falcosecurity/falco \
        --namespace falco \
        --values "$SCRIPT_DIR/../k8s/falco-values.yaml" \
        --set "falcosidekick.config.webhook.address=${WEBHOOK_URL}" \
        --wait

    print_info "Falco installed successfully!"
}

verify_falco() {
    print_info "Verifying Falco deployment..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=falco \
        -n falco --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=falcosidekick \
        -n falco --timeout=300s
    kubectl get pods -n falco
}

# ---------------------------------------------------------------------------
# Wait until FalcoLogs_CL has at least one row (i.e. the Data Collector API
# has materialised the custom table). This is required before we can create
# Sentinel scheduled analytics rules — they validate the table exists.
# ---------------------------------------------------------------------------
wait_for_falco_logs() {
    if ! $WAIT_FOR_LOGS; then
        print_warning "Skipping wait-for-logs gate (--no-wait set)."
        return 0
    fi

    print_info "Waiting for Falco events to land in Log Analytics (FalcoLogs_CL)..."
    print_info "This can take 5–15 minutes after Falco starts emitting events."
    print_info "Triggering a benign event so the table is created sooner..."

    # Generate one harmless event to nudge the pipeline. We trigger Falco's
    # "Package Management in Container" rule (apk update inside an alpine
    # container) — this is enough to exercise falcosidekick → Logic App →
    # FalcoLogs_CL without touching security-sensitive files like /etc/shadow.
    kubectl run falco-warmup --rm --restart=Never --image=alpine:3.19 -i \
        --command -- sh -c 'apk update >/dev/null 2>&1 || true; echo done' \
        >/dev/null 2>&1 || true

    local deadline=$(( $(date +%s) + WAIT_TIMEOUT_MIN * 60 ))
    local attempt=0
    while (( $(date +%s) < deadline )); do
        attempt=$((attempt + 1))
        local count
        count=$(az monitor log-analytics query \
            --workspace "$WORKSPACE_ID" \
            --analytics-query "FalcoLogs_CL | where TimeGenerated > ago(1h) | count" \
            --query "[0].Count" -o tsv 2>/dev/null || echo "")

        if [[ -n "$count" && "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
            print_info "FalcoLogs_CL is populated (rows in last 1h: $count). Proceeding."
            return 0
        fi

        print_info "  Attempt #${attempt}: FalcoLogs_CL not populated yet — sleeping 30s..."
        sleep 30
    done

    print_warning "Timed out after ${WAIT_TIMEOUT_MIN}m waiting for FalcoLogs_CL."
    print_warning "The first Sentinel rule creation may fail with 'table does not exist'."
    print_warning "Re-run: $0 --enable-rules   once data starts flowing."
    return 1
}

# ---------------------------------------------------------------------------
# Sentinel analytics rules — deterministic GUIDs (idempotent re-deploys)
# ---------------------------------------------------------------------------
# Generates a deterministic name for a rule by SHA-1-hashing
# "<workspace-id>::<displayName>" and formatting the first 32 hex chars as a
# UUID. Re-running the script with the same display name updates the existing
# rule instead of creating a duplicate.
deterministic_rule_id() {
    local workspace_resource_id="$1"
    local display_name="$2"
    local hex
    if command -v sha1sum >/dev/null 2>&1; then
        hex=$(printf '%s' "${workspace_resource_id}::${display_name}" \
            | sha1sum | awk '{print $1}' | cut -c1-32)
    else
        hex=$(printf '%s' "${workspace_resource_id}::${display_name}" \
            | shasum -a 1 | awk '{print $1}' | cut -c1-32)
    fi
    printf '%s-%s-%s-%s-%s\n' \
        "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
}

import_sentinel_rules() {
    print_info "Importing Sentinel analytics rules..."

    local rules_file="$SCRIPT_DIR/../k8s/sentinel-analytics-rules.json"
    if [[ ! -f "$rules_file" ]]; then
        print_warning "Analytics rules file not found at $rules_file"
        return
    fi

    local workspace_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LAW_NAME}"
    local rule_count
    rule_count=$(jq '.analyticsRules | length' "$rules_file")
    print_info "Found $rule_count analytics rules to import"

    local i
    for i in $(seq 0 $((rule_count - 1))); do
        local display_name rule_id tmp
        display_name=$(jq -r ".analyticsRules[$i].displayName" "$rules_file")
        rule_id=$(deterministic_rule_id "$workspace_resource_id" "$display_name")
        tmp=$(mktemp)

        jq -n --argjson r "$(jq -c ".analyticsRules[$i]" "$rules_file")" \
            '{kind: "Scheduled", properties: $r}' > "$tmp"

        print_info "  ${display_name}  (id=${rule_id})"
        if az rest --method put \
            --url "https://management.azure.com${workspace_resource_id}/providers/Microsoft.SecurityInsights/alertRules/${rule_id}?api-version=2023-02-01" \
            --body @"$tmp" \
            --output none 2>/dev/null; then
            print_info "    ✓ created/updated"
        else
            print_warning "    ✗ failed (rerun $0 --enable-rules later)"
        fi
        rm -f "$tmp"
    done
    print_info "Sentinel analytics rules import completed!"
}

# ---------------------------------------------------------------------------
# Workbook — also keyed on a deterministic GUID so re-runs update in place
# ---------------------------------------------------------------------------
deploy_workbook() {
    print_info "Deploying Falco Security Dashboard workbook..."

    local workbook_file="$SCRIPT_DIR/../workbooks/falco-security-dashboard.json"
    if [[ ! -f "$workbook_file" ]]; then
        print_warning "Workbook file not found at $workbook_file"
        return
    fi

    local workspace_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LAW_NAME}"
    local workbook_id
    workbook_id=$(deterministic_rule_id "$workspace_resource_id" "Falco Security Dashboard")
    local display_name="Falco Security Dashboard"
    local tmp
    tmp=$(mktemp)

    jq -n \
        --arg name "$workbook_id" \
        --arg displayName "$display_name" \
        --arg location "$LOCATION" \
        --arg workspaceId "$workspace_resource_id" \
        --rawfile serializedData "$workbook_file" \
        '{
            "type": "Microsoft.Insights/workbooks",
            "name": $name,
            "location": $location,
            "kind": "shared",
            "tags": {
                "hidden-sentinelWorkspaceId": $workspaceId,
                "hidden-sentinelContentType": "Workbook"
            },
            "properties": {
                "displayName": $displayName,
                "serializedData": $serializedData,
                "version": "1.0",
                "sourceId": $workspaceId,
                "category": "sentinel"
            }
        }' > "$tmp"

    if az rest --method put \
        --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/workbooks/${workbook_id}?api-version=2022-04-01" \
        --body @"$tmp" --output none 2>/dev/null; then
        print_info "✓ Workbook deployed (Monitor → Workbooks → ${display_name})"
    else
        print_warning "✗ Failed to deploy workbook"
    fi
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
display_next_steps() {
    cat <<EOF

==========================================
Deployment Complete!
==========================================

Resource Group: ${RESOURCE_GROUP}
AKS Cluster:    ${AKS_NAME}
Log Analytics:  ${LAW_NAME}

Next Steps:
  1. Open Azure Portal → Microsoft Sentinel → workspace ${LAW_NAME}
  2. Analytics → Active rules to view imported rules
  3. Monitor → Workbooks → Falco Security Dashboard
  4. Run ./scripts/simulate-attacks.sh to generate detections

Useful queries:
  FalcoLogs_CL | order by TimeGenerated desc | take 20
  FalcoLogs_CL | summarize count() by priority_s

NOTE: The Logic App callback URL is a secret and is intentionally not
printed. To inspect it locally run:
  az logic workflow show-callback-url \\
    -g ${RESOURCE_GROUP} -n ${LOGIC_APP_NAME} \\
    --trigger-name ${LOGIC_APP_TRIGGER} \\
    --query value -o tsv
EOF
}

# ---------------------------------------------------------------------------
# Helpers for `--enable-rules` only mode (no infra/Falco changes)
# ---------------------------------------------------------------------------
load_existing_outputs_or_die() {
    if ! az deployment sub show --name "$DEPLOYMENT_NAME" >/dev/null 2>&1; then
        print_error "No prior deployment named '$DEPLOYMENT_NAME' found."
        print_error "Run $0 (without --enable-rules) first."
        exit 1
    fi
    get_deployment_outputs
}

# ===========================================================================
# Main
# ===========================================================================
main() {
    print_info "Starting Falco AKS Demo Deployment (mode=${MODE})"
    print_info "===================================="

    check_prerequisites
    login_azure
    if [[ "$MODE" != "enable-rules-only" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi

    case "$MODE" in
        enable-rules-only)
            load_existing_outputs_or_die
            wait_for_falco_logs || true
            import_sentinel_rules
            deploy_workbook
            ;;
        skip-rules)
            deploy_infrastructure
            get_deployment_outputs
            fetch_webhook_url_silently
            configure_kubectl
            install_falco
            verify_falco
            print_info "Skipping Sentinel rules (per --skip-rules). Run with --enable-rules later."
            ;;
        full|*)
            deploy_infrastructure
            get_deployment_outputs
            fetch_webhook_url_silently
            configure_kubectl
            install_falco
            verify_falco
            wait_for_falco_logs || true
            import_sentinel_rules
            deploy_workbook
            display_next_steps
            ;;
    esac
}

main
