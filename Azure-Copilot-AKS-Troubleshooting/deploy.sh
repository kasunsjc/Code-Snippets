#!/bin/bash

# Deployment script for Azure Copilot AKS Troubleshooting Demo
# Deploys an AKS cluster with monitoring enabled

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
RESOURCE_GROUP_NAME="rg-copilot-aks-demo"
LOCATION="eastus"
DEPLOYMENT_NAME="copilot-aks-$(date +%Y%m%d-%H%M%S)"
AKS_CLUSTER_NAME="copilot-aks-demo"

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

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Install it with: az aks install-cli"
        exit 1
    fi

    print_message "Prerequisites check passed!"
}

create_resource_group() {
    print_message "Creating resource group: $RESOURCE_GROUP_NAME in $LOCATION..."

    az group create \
        --name "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --output table

    print_message "Resource group created!"
}

deploy_infrastructure() {
    print_message "Deploying AKS cluster with monitoring (this takes ~5 minutes)..."

    az deployment group create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$DEPLOYMENT_NAME" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --output table

    print_message "Infrastructure deployed!"
}

get_credentials() {
    print_message "Getting AKS credentials..."

    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing

    print_message "Credentials configured!"
}

verify_cluster() {
    print_message "Verifying cluster connectivity..."
    kubectl get nodes -o wide
    print_message "Cluster is ready!"
}

# Main
echo ""
echo "=============================================="
echo "  Azure Copilot AKS Troubleshooting Demo"
echo "  Infrastructure Deployment"
echo "=============================================="
echo ""

check_prerequisites
create_resource_group
deploy_infrastructure
get_credentials
verify_cluster

echo ""
echo "=============================================="
echo "  Deployment Complete!"
echo "=============================================="
echo ""
echo "  Next steps:"
echo "  1. Deploy sample apps:  cd sample-apps && ./deploy-samples.sh"
echo "  2. Open Azure Portal:   https://portal.azure.com"
echo "  3. Navigate to your AKS cluster and use Copilot!"
echo ""
