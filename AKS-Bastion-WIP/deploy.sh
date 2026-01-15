#!/bin/bash

# AKS Private Cluster with Azure Bastion - Deployment Script
# This script deploys a private AKS cluster with Azure Bastion for secure access

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_message "$YELLOW" "Checking prerequisites..."
if ! command_exists az; then
    print_message "$RED" "Error: Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! command_exists kubectl; then
    print_message "$YELLOW" "Warning: kubectl is not installed locally. It will be installed on the jumpbox VM."
fi

# Configuration
RESOURCE_GROUP="rg-aks-bastion-demo"
LOCATION="eastus"
DEPLOYMENT_NAME="aks-bastion-deployment-$(date +%s)"

print_message "$GREEN" "=== AKS Private Cluster with Azure Bastion Deployment ==="
echo ""
print_message "$YELLOW" "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  Deployment Name: $DEPLOYMENT_NAME"
echo ""

# Login to Azure (if not already logged in)
print_message "$YELLOW" "Checking Azure login status..."
az account show > /dev/null 2>&1 || {
    print_message "$YELLOW" "Not logged in. Initiating Azure login..."
    az login
}

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
print_message "$GREEN" "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Create resource group
print_message "$YELLOW" "Creating resource group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

print_message "$GREEN" "✓ Resource group created"

# Deploy Bicep template
print_message "$YELLOW" "Deploying infrastructure (this may take 10-15 minutes)..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --template-file main.bicep \
    --parameters main.bicepparam \
    --output json 2>&1)

DEPLOYMENT_EXIT_CODE=$?

if [ $DEPLOYMENT_EXIT_CODE -ne 0 ]; then
    print_message "$RED" "✗ Deployment failed!"
    echo "$DEPLOYMENT_OUTPUT"
    exit 1
fi

# Save output to file
echo "$DEPLOYMENT_OUTPUT" > deployment-output.json

print_message "$GREEN" "✓ Infrastructure deployed successfully"

# Extract outputs with error handling
AKS_CLUSTER_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.aksClusterName.value' 2>/dev/null)
BASTION_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.bastionName.value' 2>/dev/null)
BASTION_RESOURCE_ID=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.bastionResourceId.value' 2>/dev/null)
VNET_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.vnetName.value' 2>/dev/null)

# Verify we got the outputs
if [ -z "$AKS_CLUSTER_NAME" ] || [ "$AKS_CLUSTER_NAME" = "null" ]; then
    print_message "$YELLOW" "Warning: Could not extract outputs from deployment. Fetching from Azure..."
    AKS_CLUSTER_NAME=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
    BASTION_NAME=$(az network bastion list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
    BASTION_RESOURCE_ID=$(az network bastion list --resource-group "$RESOURCE_GROUP" --query "[0].id" -o tsv)
    VNET_NAME=$(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
fi

print_message "$GREEN" "=== Deployment Complete ==="
echo ""
print_message "$GREEN" "Deployed Resources:"
echo "  AKS Cluster: $AKS_CLUSTER_NAME"
echo "  Azure Bastion: $BASTION_NAME"
echo "  Virtual Network: $VNET_NAME"
echo ""

print_message "$YELLOW" "=== Next Steps ==="
echo ""
echo "1. Get AKS credentials:"
echo "   az aks get-credentials --admin --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "2. Open a tunnel to your AKS cluster using Azure Bastion:"
echo "   az aks bastion --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --admin --bastion $BASTION_RESOURCE_ID"
echo ""
echo "3. In a new terminal, set the KUBECONFIG to use the tunnel:"
echo "   export BASTION_PORT=\$(ps aux | sed -n 's/.*--port \([0-9]*\).*/\1/p' | head -1)"
echo "   sed -i \"s|server: https://.*|server: https://localhost:\${BASTION_PORT}|\" ~/.kube/config"
echo ""
echo "4. Test kubectl access:"
echo "   kubectl get nodes"
echo ""

print_message "$GREEN" "Deployment information saved to: deployment-output.json"
