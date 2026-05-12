#!/bin/bash
# =============================================================================
# VCluster Demo - Host AKS Cluster Deployment Script
# =============================================================================
# Deploys the AKS host cluster that will run all virtual cluster demos.
# Run this ONCE before starting any of the individual demo scenarios.

set -e

# Colour codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --------------------------------------------------
# Configuration — override via environment variables
# --------------------------------------------------
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-vcluster-demo}"
LOCATION="${LOCATION:-australiaeast}"
DEPLOYMENT_NAME="vcluster-demo-$(date +%s)"

print_banner() {
  echo -e "${CYAN}======================================${NC}"
  echo -e "${CYAN}  VCluster Demo — Host Cluster Setup  ${NC}"
  echo -e "${CYAN}======================================${NC}"
  echo ""
}

check_prerequisites() {
  echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

  local missing=0

  if ! command -v az &> /dev/null; then
    echo -e "${RED}  ✗ Azure CLI not found${NC}"
    echo "    Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    missing=1
  else
    echo -e "${GREEN}  ✓ Azure CLI $(az version --query '"azure-cli"' -o tsv)${NC}"
  fi

  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}  ✗ kubectl not found${NC}"
    echo "    Install: https://kubernetes.io/docs/tasks/tools/"
    missing=1
  else
    echo -e "${GREEN}  ✓ kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client)${NC}"
  fi

  if ! command -v helm &> /dev/null; then
    echo -e "${RED}  ✗ Helm not found${NC}"
    echo "    Install: https://helm.sh/docs/intro/install/"
    missing=1
  else
    echo -e "${GREEN}  ✓ Helm $(helm version --short)${NC}"
  fi

  if ! command -v vcluster &> /dev/null; then
    echo -e "${YELLOW}  ⚠ vcluster CLI not found — run install-tools.sh first${NC}"
  else
    echo -e "${GREEN}  ✓ vcluster $(vcluster version 2>/dev/null | grep 'vcluster version' | awk '{print $3}' || echo 'installed')${NC}"
  fi

  [[ $missing -eq 1 ]] && { echo -e "${RED}Please install missing tools and re-run.${NC}"; exit 1; }
  echo ""
}

azure_login_check() {
  echo -e "${YELLOW}[2/5] Checking Azure CLI login...${NC}"
  az account show &> /dev/null || {
    echo -e "${RED}  ✗ Not logged in to Azure CLI${NC}"
    echo "  Run: az login"
    exit 1
  }

  local sub_name sub_id
  sub_name=$(az account show --query name -o tsv)
  sub_id=$(az account show --query id -o tsv)
  echo -e "${GREEN}  ✓ Logged in${NC}"
  echo "    Subscription : $sub_name"
  echo "    ID           : $sub_id"
  echo ""

  read -p "  Continue with this subscription? (y/n) " -n 1 -r; echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Deployment cancelled."; exit 0; }
  echo ""
}

register_providers() {
  echo -e "${YELLOW}[3/5] Registering resource providers...${NC}"
  for provider in Microsoft.ContainerService Microsoft.OperationalInsights Microsoft.Network; do
    echo "  Registering $provider..."
    az provider register --namespace "$provider" --wait --output none
  done
  echo -e "${GREEN}  ✓ All providers registered${NC}"
  echo ""
}

create_resource_group() {
  echo -e "${YELLOW}[4/5] Creating resource group...${NC}"
  if az group exists --name "$RESOURCE_GROUP" | grep -q true; then
    echo -e "${GREEN}  ✓ Resource group '$RESOURCE_GROUP' already exists${NC}"
  else
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    echo -e "${GREEN}  ✓ Resource group '$RESOURCE_GROUP' created in '$LOCATION'${NC}"
  fi
  echo ""
}

deploy_infrastructure() {
  echo -e "${YELLOW}[5/5] Deploying AKS host cluster via Bicep...${NC}"
  echo "  This takes ~5-10 minutes..."
  echo ""

  az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$(dirname "$0")/main.bicep" \
    --parameters "$(dirname "$0")/main.bicepparam" \
    --output table

  echo ""
  echo -e "${GREEN}  ✓ Infrastructure deployed${NC}"
}

get_credentials() {
  local cluster_name
  cluster_name=$(az deployment group show \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query properties.outputs.aksClusterName.value -o tsv)

  echo ""
  echo -e "${YELLOW}Getting AKS credentials...${NC}"
  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$cluster_name" \
    --overwrite-existing

  echo -e "${GREEN}  ✓ kubeconfig updated — context: $cluster_name${NC}"

  echo ""
  echo -e "${CYAN}==================================================${NC}"
  echo -e "${GREEN}  Host cluster ready!${NC}"
  echo -e "${CYAN}==================================================${NC}"
  echo ""
  echo "  Cluster name : $cluster_name"
  echo "  Resource group: $RESOURCE_GROUP"
  echo ""
  echo -e "${YELLOW}  Next steps:${NC}"
  echo "  1. Run install-tools.sh to install the vcluster CLI"
  echo "  2. Navigate to 01-basic-vcluster/ and follow the README"
  echo ""
}

# --------------------------------------------------
# Main
# --------------------------------------------------
print_banner
check_prerequisites
azure_login_check
register_providers
create_resource_group
deploy_infrastructure
get_credentials
