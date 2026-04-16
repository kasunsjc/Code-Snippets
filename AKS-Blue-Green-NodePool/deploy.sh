#!/bin/bash
set -euo pipefail

# ============================================================
# Deploy AKS with Blue-Green Node Pool Strategy
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
    print_warning "This deployment may take 5-10 minutes..."

    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --output table

    print_message "Deployment completed successfully!"
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
    print_message "Deploying sample application to blue node pool..."

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
    echo "Nodes with labels:"
    kubectl get nodes --show-labels | grep -E "NAME|environment"

    echo ""
    echo "Pods on blue nodes:"
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
    echo "Kubernetes Version:    $K8S_VERSION"
    echo ""
    echo "=========================================="
    echo "   Node Pools"
    echo "=========================================="
    echo ""
    echo "  ✅ systempool  — System node pool"
    echo "  🔵 blue        — User node pool (active)"
    echo ""
    echo "=========================================="
    echo "   Next Steps"
    echo "=========================================="
    echo ""
    echo "1. Verify the sample app is running on blue nodes:"
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
    create_resource_group
    deploy_bicep
    configure_aks_access
    deploy_sample_app
    verify_deployment
    display_summary

    print_message "Deployment completed successfully!"
}

main
