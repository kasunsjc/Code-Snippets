#!/bin/bash
set -euo pipefail

# ============================================================
# Deploy AKS with Blue-Green Node Pool Upgrade Strategy (Preview)
# ============================================================
# This script deploys an AKS cluster and configures the user
# node pool with the blue-green upgrade strategy using the
# aks-preview CLI extension.
#
# Reference:
# https://learn.microsoft.com/en-us/azure/aks/blue-green-node-pool-upgrade
# ============================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="aks-bluegreen-demo"
LOCATION="northeurope"
CLUSTER_NAME="aks-bluegreen-cluster"
NODEPOOL_NAME="userpool"
DEPLOYMENT_NAME="bluegreen-deployment-$(date +%Y%m%d-%H%M%S)"

# Functions
print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

check_prerequisites() {
    print_message "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    print_message "Azure CLI version: $AZ_VERSION"

    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is not installed. Install it to run the demo steps."
    fi

    print_message "Prerequisites check passed!"
}

install_aks_preview() {
    print_message "Installing/updating aks-preview CLI extension..."

    if az extension show --name aks-preview &> /dev/null; then
        az extension update --name aks-preview --only-show-errors || true
        print_message "aks-preview extension updated!"
    else
        az extension add --name aks-preview --only-show-errors
        print_message "aks-preview extension installed!"
    fi

    AKS_PREVIEW_VERSION=$(az extension show --name aks-preview --query version -o tsv)
    print_message "aks-preview extension version: $AKS_PREVIEW_VERSION"
}

select_kubernetes_version() {
    print_message "Fetching available Kubernetes versions in $LOCATION..."

    # Get available versions and store in an array (avoid mapfile for macOS Bash 3.x compatibility)
    AVAILABLE_VERSIONS=()
    while IFS= read -r line; do
        AVAILABLE_VERSIONS+=("$line")
    done < <(az aks get-versions \
        --location "$LOCATION" \
        --query "values[].patchVersions.keys(@)[]" \
        --output tsv 2>/dev/null | sort -V)

    if [ ${#AVAILABLE_VERSIONS[@]} -eq 0 ]; then
        print_error "Could not retrieve available Kubernetes versions."
        exit 1
    fi

    echo ""
    print_message "Available Kubernetes versions in $LOCATION:"
    echo ""
    for i in "${!AVAILABLE_VERSIONS[@]}"; do
        printf "  [%2d] %s\n" "$((i + 1))" "${AVAILABLE_VERSIONS[$i]}"
    done
    echo ""

    while true; do
        read -p "Select the Kubernetes version to deploy (enter number 1-${#AVAILABLE_VERSIONS[@]}): " selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#AVAILABLE_VERSIONS[@]}" ]; then
            SELECTED_K8S_VERSION="${AVAILABLE_VERSIONS[$((selection - 1))]}"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#AVAILABLE_VERSIONS[@]}."
        fi
    done

    print_message "Selected Kubernetes version: $SELECTED_K8S_VERSION"
}

create_resource_group() {
    print_message "Creating resource group: $RESOURCE_GROUP in $LOCATION..."

    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output table

    print_message "Resource group created successfully!"
}

deploy_bicep() {
    print_message "Starting Bicep deployment: $DEPLOYMENT_NAME..."
    print_message "Deploying with Kubernetes version: $SELECTED_K8S_VERSION"
    print_warning "This deployment may take 5-10 minutes..."

    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --parameters kubernetesVersion="$SELECTED_K8S_VERSION" \
        --output table

    print_message "Deployment completed successfully!"
}

configure_bluegreen_strategy() {
    print_message "Configuring blue-green upgrade strategy on node pool: $NODEPOOL_NAME..."

    az aks nodepool update \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --upgrade-strategy bluegreen \
        --drain-batch-size "50%" \
        --drain-timeout-bg 30 \
        --batch-soak-duration 5 \
        --final-soak-duration 60 \
        --output table

    print_message "Blue-green upgrade strategy configured!"
}

configure_aks_access() {
    print_message "Configuring AKS cluster access..."

    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --overwrite-existing

    print_message "AKS credentials configured!"
}

deploy_sample_app() {
    print_message "Deploying sample application..."

    kubectl create ns demo 2>/dev/null || true
    kubectl apply -f sample-deployment.yaml -n demo

    print_message "Waiting for pods to be ready..."
    kubectl rollout status deployment/sample-app -n demo --timeout=120s

    print_message "Sample application deployed!"
}

verify_deployment() {
    print_message "Verifying cluster and node pools..."

    echo ""
    echo "Node Pools:"
    az aks nodepool list \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table

    echo ""
    echo "Node Pool Upgrade Strategy:"
    az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query "{name:name, upgradeSettings:upgradeSettings}" \
        --output json

    echo ""
    echo "Nodes:"
    kubectl get nodes -o wide

    echo ""
    echo "Sample app pods:"
    kubectl get pods -n demo -o wide

    print_message "Verification complete!"
}

display_summary() {
    CLUSTER_FQDN=$(az aks show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query fqdn \
        --output tsv)

    K8S_VERSION=$(az aks show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query kubernetesVersion \
        --output tsv)

    echo ""
    echo "=========================================="
    echo "   Deployment Summary"
    echo "=========================================="
    echo ""
    echo "Resource Group:        $RESOURCE_GROUP"
    echo "AKS Cluster:           $CLUSTER_NAME"
    echo "Cluster FQDN:          $CLUSTER_FQDN"
    echo "Kubernetes Version:    $K8S_VERSION (user-selected at deploy time)"
    echo ""
    echo "=========================================="
    echo "   Node Pool Configuration"
    echo "=========================================="
    echo ""
    echo "  ✅ systempool  — System node pool (rolling)"
    echo "  🔵 userpool    — User node pool (blue-green)"
    echo ""
    echo "  Blue-Green Upgrade Settings:"
    echo "    Drain Batch Size:        50%"
    echo "    Drain Timeout:           30 minutes"
    echo "    Batch Soak Duration:     5 minutes"
    echo "    Final Soak Duration:     60 minutes"
    echo ""
    echo "=========================================="
    echo "   Next Steps"
    echo "=========================================="
    echo ""
    echo "1. Verify the sample app is running:"
    echo "   kubectl get pods -n demo -o wide"
    echo ""
    echo "2. Run the blue-green upgrade demo:"
    echo "   ./blue-green-upgrade.sh"
    echo ""
    echo "3. See README.md for full walkthrough"
    echo ""
    echo "=========================================="
    echo ""
}

# Main execution
main() {
    print_message "Starting AKS Blue-Green Node Pool deployment..."

    check_prerequisites
    install_aks_preview
    select_kubernetes_version
    create_resource_group
    deploy_bicep
    configure_bluegreen_strategy
    configure_aks_access
    deploy_sample_app
    verify_deployment
    display_summary

    print_message "Deployment completed successfully!"
}

main
