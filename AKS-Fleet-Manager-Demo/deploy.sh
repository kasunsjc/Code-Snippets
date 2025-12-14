#!/bin/bash

# AKS Fleet Manager Demo - Deployment Script
# This script deploys the entire Fleet Manager infrastructure

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENT_NAME="aks-fleet-deployment-$(date +%s)"
LOCATION="eastus"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}AKS Fleet Manager Demo Deployment${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
echo -e "${YELLOW}Checking Azure CLI login status...${NC}"
az account show &> /dev/null || {
    echo -e "${RED}Error: Not logged in to Azure CLI${NC}"
    echo "Please run: az login"
    exit 1
}

echo -e "${GREEN}✓ Azure CLI login verified${NC}"
echo ""

# Display current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${YELLOW}Current Subscription:${NC}"
echo "  Name: $SUBSCRIPTION_NAME"
echo "  ID: $SUBSCRIPTION_ID"
echo ""

read -p "Continue with this subscription? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Register required resource providers
echo -e "${YELLOW}Registering required resource providers...${NC}"
az provider register --namespace Microsoft.ContainerService --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Network --wait
echo -e "${GREEN}✓ Resource providers registered${NC}"
echo ""

# Deploy infrastructure (resource group will be created by Bicep)
echo -e "${YELLOW}Deploying AKS Fleet Manager infrastructure...${NC}"
echo "This will create the resource group and all resources."
echo "This may take 15-20 minutes..."
echo ""

az deployment sub create \
    --name $DEPLOYMENT_NAME \
    --location $LOCATION \
    --template-file main.bicep \
    --parameters main.bicepparam \
    --output table

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Infrastructure deployment completed successfully${NC}"
else
    echo -e "${RED}✗ Infrastructure deployment failed${NC}"
    exit 1
fi
echo ""

# Get deployment outputs
echo -e "${YELLOW}Retrieving deployment outputs...${NC}"
RESOURCE_GROUP=$(az deployment sub show \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs.resourceGroupName.value -o tsv)

FLEET_NAME=$(az deployment sub show \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs.fleetName.value -o tsv)

MEMBER_CLUSTER1=$(az deployment sub show \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs.memberCluster1Name.value -o tsv)

MEMBER_CLUSTER2=$(az deployment sub show \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs.memberCluster2Name.value -o tsv)

echo -e "${GREEN}✓ Deployment outputs retrieved${NC}"
echo ""

# Display deployment summary
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deployment Summary${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${YELLOW}Resource Group:${NC} $RESOURCE_GROUP"
echo -e "${YELLOW}Fleet Manager:${NC} $FLEET_NAME"
echo -e "${YELLOW}Member Cluster 1:${NC} $MEMBER_CLUSTER1"
echo -e "${YELLOW}Member Cluster 2:${NC} $MEMBER_CLUSTER2"
echo ""

# Get credentials
echo -e "${YELLOW}Getting cluster credentials...${NC}"
az fleet get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $FLEET_NAME \
    --context fleet-hub \
    --overwrite-existing

az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $MEMBER_CLUSTER1 \
    --context $MEMBER_CLUSTER1 \
    --overwrite-existing

az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $MEMBER_CLUSTER2 \
    --context $MEMBER_CLUSTER2 \
    --overwrite-existing

echo -e "${GREEN}✓ Cluster credentials configured${NC}"
echo ""

# Assign RBAC role to current user
echo -e "${YELLOW}Assigning Fleet Manager RBAC role to current user...${NC}"
CURRENT_USER_EMAIL=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)

if [ -z "$CURRENT_USER_OBJECT_ID" ]; then
    echo -e "${YELLOW}⚠ Warning: Could not get current user's Object ID${NC}"
    echo "You may need to manually assign the role later."
else
    echo -e "  User: $CURRENT_USER_EMAIL"
    echo -e "  Object ID: $CURRENT_USER_OBJECT_ID"
    
    # Azure Kubernetes Fleet Manager RBAC Cluster Admin role ID
    ROLE_ID="18ab4d3d-a1bf-4477-8ad9-8359bc988f69"
    FLEET_RESOURCE_ID=$(az fleet show --resource-group $RESOURCE_GROUP --name $FLEET_NAME --query id -o tsv)
    
    az role assignment create \
        --assignee $CURRENT_USER_OBJECT_ID \
        --role $ROLE_ID \
        --scope $FLEET_RESOURCE_ID \
        --output none 2>/dev/null || echo -e "${YELLOW}⚠ Role may already be assigned${NC}"
    
    echo -e "${GREEN}✓ Fleet Manager RBAC role assigned${NC}"
fi
echo ""

# Display kubectl contexts
echo -e "${YELLOW}Available kubectl contexts:${NC}"
kubectl config get-contexts
echo ""

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Next steps:"
echo "1. Switch to fleet hub context: kubectl config use-context fleet-hub"
echo "2. Deploy sample applications: ./deploy-samples.sh"
echo "3. View fleet status: kubectl get clusters"
echo ""
