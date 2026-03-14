#!/bin/bash

# AKS Fleet Manager - Connect Standalone Cluster Demo
# This script demonstrates how to connect an existing standalone AKS cluster to a Fleet Manager

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}  AKS Fleet Manager - Connect Standalone Cluster Demo  ${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo ""

# Check if resource group parameter is provided
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 <resource-group-name> [cluster-name]${NC}"
    echo ""
    echo "Examples:"
    echo "  $0 rg-aks-fleet-demo-01"
    echo "  $0 rg-aks-fleet-demo-01 aks-dev-2-demo"
    exit 1
fi

RESOURCE_GROUP=$1
CLUSTER_NAME=${2:-""}

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

# Get subscription info
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${BLUE}Current Subscription:${NC}"
echo "  Name: $SUBSCRIPTION_NAME"
echo "  ID: $SUBSCRIPTION_ID"
echo ""

# Check if resource group exists
echo -e "${YELLOW}Checking if resource group exists...${NC}"
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    echo -e "${RED}Error: Resource group '$RESOURCE_GROUP' not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Resource group found${NC}"
echo ""

# Get Fleet Manager name
echo -e "${YELLOW}Finding Fleet Manager in resource group...${NC}"
FLEET_NAME=$(az fleet list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)

if [ -z "$FLEET_NAME" ]; then
    echo -e "${RED}Error: No Fleet Manager found in resource group '$RESOURCE_GROUP'${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Fleet Manager found: ${FLEET_NAME}${NC}"
echo ""

# If cluster name not provided, try to find standalone cluster
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${YELLOW}Looking for standalone AKS clusters (not connected to fleet)...${NC}"
    
    # Get all AKS clusters in the resource group
    ALL_CLUSTERS=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)
    
    # Get clusters already in the fleet
    FLEET_MEMBERS=$(az fleet member list --fleet-name "$FLEET_NAME" --resource-group "$RESOURCE_GROUP" --query "[].clusterResourceId" -o tsv 2>/dev/null | awk -F'/' '{print $NF}' || echo "")
    
    # Find standalone clusters
    STANDALONE_CLUSTERS=()
    for cluster in $ALL_CLUSTERS; do
        if ! echo "$FLEET_MEMBERS" | grep -q "^${cluster}$"; then
            STANDALONE_CLUSTERS+=("$cluster")
        fi
    done
    
    if [ ${#STANDALONE_CLUSTERS[@]} -eq 0 ]; then
        echo -e "${RED}Error: No standalone clusters found${NC}"
        echo "All clusters are already connected to the fleet."
        exit 1
    fi
    
    echo -e "${GREEN}Found ${#STANDALONE_CLUSTERS[@]} standalone cluster(s):${NC}"
    for i in "${!STANDALONE_CLUSTERS[@]}"; do
        echo "  $((i+1)). ${STANDALONE_CLUSTERS[$i]}"
    done
    echo ""
    
    # Use first standalone cluster
    CLUSTER_NAME="${STANDALONE_CLUSTERS[0]}"
    echo -e "${BLUE}Using cluster: ${CLUSTER_NAME}${NC}"
    echo ""
fi

# Get cluster resource ID
echo -e "${YELLOW}Getting cluster resource ID...${NC}"
CLUSTER_RESOURCE_ID=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

if [ -z "$CLUSTER_RESOURCE_ID" ]; then
    echo -e "${RED}Error: Cluster '$CLUSTER_NAME' not found in resource group '$RESOURCE_GROUP'${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Cluster resource ID: ${CLUSTER_RESOURCE_ID}${NC}"
echo ""

# Check if cluster is already a fleet member
echo -e "${YELLOW}Checking if cluster is already a fleet member...${NC}"
EXISTING_MEMBER=$(az fleet member list --fleet-name "$FLEET_NAME" --resource-group "$RESOURCE_GROUP" --query "[?clusterResourceId=='$CLUSTER_RESOURCE_ID'].name" -o tsv 2>/dev/null || echo "")

if [ ! -z "$EXISTING_MEMBER" ]; then
    echo -e "${YELLOW}⚠ Cluster is already a member of the fleet with name: ${EXISTING_MEMBER}${NC}"
    echo ""
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# Create member name
MEMBER_NAME="${CLUSTER_NAME}-member"

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Connection Details:${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "  Fleet Manager:  ${GREEN}${FLEET_NAME}${NC}"
echo -e "  Cluster:        ${GREEN}${CLUSTER_NAME}${NC}"
echo -e "  Member Name:    ${GREEN}${MEMBER_NAME}${NC}"
echo -e "  Resource Group: ${GREEN}${RESOURCE_GROUP}${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

read -p "Connect this cluster to the fleet? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Connect cluster to fleet
echo ""
echo -e "${YELLOW}Connecting cluster to fleet...${NC}"
echo "This may take a few minutes..."
echo ""

az fleet member create \
    --fleet-name "$FLEET_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MEMBER_NAME" \
    --member-cluster-id "$CLUSTER_RESOURCE_ID" \
    --output table

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Cluster successfully connected to fleet!${NC}"
    echo ""
    
    # Verify membership
    echo -e "${YELLOW}Verifying fleet membership...${NC}"
    az fleet member show \
        --fleet-name "$FLEET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MEMBER_NAME" \
        --output table
    
    echo ""
    echo -e "${GREEN}=======================================================${NC}"
    echo -e "${GREEN}  Connection Complete!${NC}"
    echo -e "${GREEN}=======================================================${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. List all fleet members:"
    echo -e "     ${YELLOW}az fleet member list --fleet-name $FLEET_NAME --resource-group $RESOURCE_GROUP --output table${NC}"
    echo ""
    echo "  2. Get fleet hub credentials:"
    echo -e "     ${YELLOW}az fleet get-credentials --resource-group $RESOURCE_GROUP --name $FLEET_NAME${NC}"
    echo ""
    echo "  3. Deploy resources to the newly connected cluster using ClusterResourcePlacement"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Failed to connect cluster to fleet${NC}"
    exit 1
fi
