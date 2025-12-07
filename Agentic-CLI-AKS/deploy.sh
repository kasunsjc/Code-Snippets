#!/bin/bash

# Deployment script for Agentic CLI AKS Demo
# This script deploys the AKS cluster and Azure OpenAI resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
RESOURCE_GROUP_NAME="rg-aksagent-demo"
LOCATION="eastus"
DEPLOYMENT_NAME="aksagent-deployment-$(date +%Y%m%d-%H%M%S)"

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
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
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
    
    print_message "Resource group created successfully!"
}

deploy_bicep() {
    print_message "Starting Bicep deployment: $DEPLOYMENT_NAME..."
    print_warning "This deployment may take 10-15 minutes..."
    
    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --output table
    
    print_message "Deployment completed successfully!"
}

get_outputs() {
    print_message "Retrieving deployment outputs..."
    
    AKS_CLUSTER_NAME=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query properties.outputs.aksClusterName.value \
        --output tsv)
    
    OPENAI_ENDPOINT=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query properties.outputs.openAiEndpoint.value \
        --output tsv)
    
    OPENAI_NAME=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query properties.outputs.openAiName.value \
        --output tsv)
    
    MODEL_DEPLOYMENT_NAME=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query properties.outputs.openAiModelDeploymentName.value \
        --output tsv)
    
    ACR_LOGIN_SERVER=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query properties.outputs.acrLoginServer.value \
        --output tsv)
    
    print_message "Outputs retrieved successfully!"
}

configure_aks_access() {
    print_message "Configuring AKS cluster access..."
    
    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing
    
    print_message "AKS credentials configured!"
}

get_openai_key() {
    print_message "Retrieving Azure OpenAI API key..."
    
    OPENAI_API_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query key1 \
        --output tsv)
    
    print_message "API key retrieved successfully!"
}

display_summary() {
    echo ""
    echo "=========================================="
    echo "   Deployment Summary"
    echo "=========================================="
    echo ""
    echo "Resource Group:        $RESOURCE_GROUP_NAME"
    echo "AKS Cluster:          $AKS_CLUSTER_NAME"
    echo "OpenAI Resource:      $OPENAI_NAME"
    echo "OpenAI Endpoint:      $OPENAI_ENDPOINT"
    echo "Model Deployment:     $MODEL_DEPLOYMENT_NAME"
    echo "ACR Login Server:     $ACR_LOGIN_SERVER"
    echo ""
    echo "=========================================="
    echo "   Next Steps"
    echo "=========================================="
    echo ""
    echo "1. Install the AKS agent extension:"
    echo "   az extension add --name aks-agent --debug"
    echo ""
    echo "2. Initialize the agent with Azure OpenAI:"
    echo "   az aks agent-init"
    echo ""
    echo "   Use these values when prompted:"
    echo "   - Provider: Azure OpenAI (option 1)"
    echo "   - Model Name: $MODEL_DEPLOYMENT_NAME"
    echo "   - API Base: $OPENAI_ENDPOINT"
    echo "   - API Key: $OPENAI_API_KEY"
    echo "   - API Version: 2024-08-01-preview"
    echo ""
    echo "3. Start using the agent:"
    echo "   az aks agent \"How many nodes are in my cluster?\""
    echo ""
    echo "=========================================="
    echo ""
}

# Main execution
main() {
    print_message "Starting Agentic CLI AKS Demo deployment..."
    
    check_prerequisites
    create_resource_group
    deploy_bicep
    get_outputs
    configure_aks_access
    get_openai_key
    display_summary
    
    print_message "Deployment completed successfully!"
}

# Run main function
main
