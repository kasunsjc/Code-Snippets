#!/bin/bash
# ========================================
# Deployment Script for Falco AKS Demo
# ========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="rg-falco-demo"
LOCATION="eastus"
SUBSCRIPTION_ID=""

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it from https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install it from https://helm.sh/docs/intro/install/"
        exit 1
    fi
    
    print_info "All prerequisites are met!"
}

login_azure() {
    print_info "Checking Azure login status..."
    
    if ! az account show &> /dev/null; then
        print_info "Not logged in to Azure. Logging in..."
        az login
    fi
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    print_info "Using subscription: $SUBSCRIPTION_ID"
}

create_resource_group() {
    print_info "Resource group will be created by Bicep deployment..."
}

deploy_infrastructure() {
    print_info "Deploying Azure infrastructure with Bicep (subscription-level deployment)..."
    
    # Get the current user's object ID for RBAC
    print_info "Getting current user's object ID for AKS RBAC assignment..."
    USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
    print_info "User Object ID: $USER_OBJECT_ID"
    
    az deployment sub create \
        --location eastus \
        --template-file ../main-subscription.bicep \
        --parameters ../main-subscription.bicepparam \
        --parameters aksAdminPrincipalId="$USER_OBJECT_ID" \
        --output table
    
    print_info "Infrastructure deployed successfully!"
}

get_deployment_outputs() {
    print_info "Retrieving deployment outputs..."
    
    RESOURCE_GROUP=$(az deployment sub show \
        --name main-subscription \
        --query properties.outputs.resourceGroupName.value -o tsv)
    
    AKS_NAME=$(az deployment sub show \
        --name main-subscription \
        --query properties.outputs.aksClusterName.value -o tsv)
    
    LAW_NAME=$(az deployment sub show \
        --name main-subscription \
        --query properties.outputs.logAnalyticsWorkspaceName.value -o tsv)
    
    WORKSPACE_ID=$(az deployment sub show \
        --name main-subscription \
        --query properties.outputs.workspaceCustomerId.value -o tsv)
    
    WEBHOOK_URL=$(az deployment sub show \
        --name main-subscription \
        --query properties.outputs.logicAppWebhookUrl.value -o tsv)
    
    print_info "Resource Group: $RESOURCE_GROUP"
    print_info "AKS Cluster: $AKS_NAME"
    print_info "Log Analytics Workspace: $LAW_NAME"
    print_info "Workspace ID: $WORKSPACE_ID"
    print_info "Logic App Webhook URL: $WEBHOOK_URL"
}

configure_kubectl() {
    print_info "Configuring kubectl..."
    
    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AKS_NAME" \
        --overwrite-existing
    
    print_info "kubectl configured successfully!"
    kubectl cluster-info
}

install_falco() {
    print_info "Installing Falco on AKS cluster..."
    
    # Add Falco Helm repository
    helm repo add falcosecurity https://falcosecurity.github.io/charts
    helm repo update
    
    # Create namespace
    kubectl apply -f ../k8s/falco-namespace.yaml
    
    # Install Falco with Falcosidekick configured to use Logic App webhook
    helm upgrade --install falco falcosecurity/falco \
        --namespace falco \
        --values ../k8s/falco-values.yaml \
        --set falcosidekick.config.webhook.address="$WEBHOOK_URL" \
        --wait
    
    print_info "Falco installed successfully!"
    print_info "Falcosidekick configured to send alerts to Logic App webhook"
}

verify_deployment() {
    print_info "Verifying deployment..."
    
    print_info "Checking Falco pods:"
    kubectl get pods -n falco
    
    print_info "\nWaiting for Falco pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=falco -n falco --timeout=300s
    
    print_info "\nWaiting for Falcosidekick pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=falcosidekick -n falco --timeout=300s
    
    print_info "\nChecking Falco logs:"
    kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
    
    print_info "\nChecking Falcosidekick logs:"
    kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick --tail=20
    
    print_info "\nDeployment verification complete!"
}

import_sentinel_rules() {
    print_info "Importing Sentinel analytics rules..."
    
    # Get workspace resource ID
    WORKSPACE_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LAW_NAME"
    
    # Read the analytics rules JSON file
    RULES_FILE="../k8s/sentinel-analytics-rules.json"
    
    if [ ! -f "$RULES_FILE" ]; then
        print_warning "Analytics rules file not found at $RULES_FILE"
        return
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Skipping Sentinel rules import."
        print_info "Install jq with: brew install jq (macOS) or apt-get install jq (Linux)"
        return
    fi
    
    # Parse and create each rule
    RULE_COUNT=$(jq '.analyticsRules | length' "$RULES_FILE")
    print_info "Found $RULE_COUNT analytics rules to import"
    
    for i in $(seq 0 $((RULE_COUNT - 1))); do
        RULE_NAME=$(jq -r ".analyticsRules[$i].displayName" "$RULES_FILE")
        print_info "Creating rule: $RULE_NAME"
        
        # Generate a unique GUID for the rule
        RULE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
        
        # Create a temporary JSON file for the rule body
        TEMP_BODY=$(mktemp)
        
        # Build the rule JSON
        jq -n \
            --arg displayName "$(jq -r ".analyticsRules[$i].displayName" "$RULES_FILE")" \
            --arg description "$(jq -r ".analyticsRules[$i].description" "$RULES_FILE")" \
            --arg severity "$(jq -r ".analyticsRules[$i].severity" "$RULES_FILE")" \
            --argjson enabled $(jq -r ".analyticsRules[$i].enabled" "$RULES_FILE") \
            --arg query "$(jq -r ".analyticsRules[$i].query" "$RULES_FILE")" \
            --arg queryFrequency "$(jq -r ".analyticsRules[$i].queryFrequency" "$RULES_FILE")" \
            --arg queryPeriod "$(jq -r ".analyticsRules[$i].queryPeriod" "$RULES_FILE")" \
            --arg triggerOperator "$(jq -r ".analyticsRules[$i].triggerOperator" "$RULES_FILE")" \
            --argjson triggerThreshold $(jq -r ".analyticsRules[$i].triggerThreshold" "$RULES_FILE") \
            --arg suppressionDuration "$(jq -r ".analyticsRules[$i].suppressionDuration" "$RULES_FILE")" \
            --argjson suppressionEnabled $(jq -r ".analyticsRules[$i].suppressionEnabled" "$RULES_FILE") \
            --argjson tactics $(jq -c ".analyticsRules[$i].tactics" "$RULES_FILE") \
            --argjson techniques $(jq -c ".analyticsRules[$i].techniques" "$RULES_FILE") \
            '{
                "kind": "Scheduled",
                "properties": {
                    "displayName": $displayName,
                    "description": $description,
                    "severity": $severity,
                    "enabled": $enabled,
                    "query": $query,
                    "queryFrequency": $queryFrequency,
                    "queryPeriod": $queryPeriod,
                    "triggerOperator": $triggerOperator,
                    "triggerThreshold": $triggerThreshold,
                    "suppressionDuration": $suppressionDuration,
                    "suppressionEnabled": $suppressionEnabled,
                    "tactics": $tactics,
                    "techniques": $techniques
                }
            }' > "$TEMP_BODY"
        
        # Create the analytics rule using Azure REST API
        if az rest --method put \
            --url "https://management.azure.com${WORKSPACE_RESOURCE_ID}/providers/Microsoft.SecurityInsights/alertRules/${RULE_ID}?api-version=2023-02-01" \
            --body @"$TEMP_BODY" \
            --output none 2>&1; then
            print_info "✓ Successfully created rule: $RULE_NAME"
        else
            print_warning "✗ Failed to create rule: $RULE_NAME"
        fi
        
        # Clean up temp file
        rm -f "$TEMP_BODY"
    done
    
    print_info "Sentinel analytics rules import completed!"
}

deploy_workbook() {
    print_info "Deploying Falco Security Dashboard workbook..."
    
    # Get workspace resource ID
    WORKSPACE_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LAW_NAME"
    
    # Workbook file path
    WORKBOOK_FILE="../workbooks/falco-security-dashboard.json"
    
    if [ ! -f "$WORKBOOK_FILE" ]; then
        print_warning "Workbook file not found at $WORKBOOK_FILE"
        return
    fi
    
    # Generate a unique GUID for the workbook
    WORKBOOK_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    
    # Create the workbook using Azure REST API
    print_info "Creating workbook: Falco Security Dashboard"
    
    # Build the workbook resource JSON
    TEMP_WORKBOOK=$(mktemp)
    
    jq -n \
        --arg name "$WORKBOOK_ID" \
        --arg displayName "Falco Security Dashboard" \
        --arg location "$LOCATION" \
        --arg workspaceId "$WORKSPACE_RESOURCE_ID" \
        --rawfile serializedData "$WORKBOOK_FILE" \
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
        }' > "$TEMP_WORKBOOK"
    
    if az rest --method put \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/workbooks/${WORKBOOK_ID}?api-version=2022-04-01" \
        --body @"$TEMP_WORKBOOK" \
        --output none 2>&1; then
        print_info "✓ Successfully deployed Falco Security Dashboard workbook"
        print_info "View workbook in Azure Portal: Monitor > Workbooks > $displayName"
    else
        print_warning "✗ Failed to deploy workbook"
    fi
    
    # Clean up temp file
    rm -f "$TEMP_WORKBOOK"
    
    print_info "Workbook deployment completed!"
}

display_next_steps() {
    print_info "\n=========================================="
    print_info "Deployment Complete!"
    print_info "=========================================="
    echo ""
    print_info "Next Steps:"
    echo "1. Access Azure Portal and navigate to Microsoft Sentinel"
    echo "2. Select the workspace: $LAW_NAME"
    echo "3. Go to Analytics > Active rules to view imported rules"
    echo "4. View Falco Security Dashboard: Monitor > Workbooks > Falco Security Dashboard"
    echo "5. Test Falco by running: kubectl run test-pod --image=alpine --rm -it -- sh"
    echo "6. Check logs in Log Analytics with query: FalcoLogs_CL | take 10"
    echo ""
    print_info "Logic App Webhook:"
    echo "- Webhook URL: $WEBHOOK_URL"
    echo "- View Logic App runs in Azure Portal: Logic Apps > logic-falco-webhook > Overview"
    echo ""
    print_info "Useful Commands:"
    echo "- View Falco logs: kubectl logs -n falco -l app.kubernetes.io/name=falco -f"
    echo "- View Falcosidekick logs: kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick -f"
    echo "- Test with a violation: kubectl exec -it <pod-name> -- cat /etc/shadow"
    echo ""
}

# Main execution
main() {
    print_info "Starting Falco AKS Demo Deployment"
    print_info "===================================="
    
    check_prerequisites
    login_azure
    create_resource_group
    deploy_infrastructure
    get_deployment_outputs
    configure_kubectl
    install_falco
    verify_deployment
    import_sentinel_rules
    deploy_workbook
    display_next_steps
}

# Run main function
main
