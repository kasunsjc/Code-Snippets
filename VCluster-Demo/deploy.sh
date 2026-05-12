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
  # PURPOSE: Verify that all required CLI tools are installed before deployment
  # This prevents failures mid-deployment due to missing tools
  echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

  local missing=0

  # Check for Azure CLI — required for az commands (login, provider registration, resource creation)
  if ! command -v az &> /dev/null; then
    echo -e "${RED}  ✗ Azure CLI not found${NC}"
    echo "    Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    missing=1
  else
    # Extract version using az version and extract just the version number
    # Format: "azure-cli" : "2.56.0" → outputs 2.56.0
    echo -e "${GREEN}  ✓ Azure CLI $(az version --query '"azure-cli"' -o tsv)${NC}"
  fi

  # Check for kubectl — required for Kubernetes cluster access and resource management
  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}  ✗ kubectl not found${NC}"
    echo "    Install: https://kubernetes.io/docs/tasks/tools/"
    missing=1
  else
    # Get kubectl client version; --short flag gives compact output format
    echo -e "${GREEN}  ✓ kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client)${NC}"
  fi

  # Check for Helm — required for installing NGINX Ingress Controller and other Helm charts
  if ! command -v helm &> /dev/null; then
    echo -e "${RED}  ✗ Helm not found${NC}"
    echo "    Install: https://helm.sh/docs/intro/install/"
    missing=1
  else
    # Get Helm version in short format (e.g., "v3.14.0")
    echo -e "${GREEN}  ✓ Helm $(helm version --short)${NC}"
  fi

  # Check for vcluster CLI — required for vcluster management (create, connect, delete)
  # Note: This is optional at this stage; install-tools.sh can be run before each demo
  if ! command -v vcluster &> /dev/null; then
    echo -e "${YELLOW}  ⚠ vcluster CLI not found — run install-tools.sh first${NC}"
  else
    # Get vcluster version; grep extracts "vcluster version X.X.X", awk extracts version number
    echo -e "${GREEN}  ✓ vcluster $(vcluster version 2>/dev/null | grep 'vcluster version' | awk '{print $3}' || echo 'installed')${NC}"
  fi

  # Exit if any critical tool is missing
  [[ $missing -eq 1 ]] && { echo -e "${RED}Please install missing tools and re-run.${NC}"; exit 1; }
  echo ""
}

azure_login_check() {
  # PURPOSE: Verify Azure CLI authentication and get current subscription details
  # This ensures the user is logged in and using the correct subscription before deployment
  echo -e "${YELLOW}[2/5] Checking Azure CLI login...${NC}"

  # Try to show current account; if not logged in, fails silently (2>/dev/null)
  az account show &> /dev/null || {
    echo -e "${RED}  ✗ Not logged in to Azure CLI${NC}"
    echo "  Run: az login"
    exit 1
  }

  # Extract subscription name and ID from current context
  # 'az account show' outputs JSON; --query extracts specific fields; -o tsv outputs as tab-separated values
  local sub_name sub_id
  sub_name=$(az account show --query name -o tsv)
  sub_id=$(az account show --query id -o tsv)
  
  echo -e "${GREEN}  ✓ Logged in${NC}"
  echo "    Subscription : $sub_name"
  echo "    ID           : $sub_id"
  echo ""

  # Prompt user to confirm subscription before proceeding
  # -n 1: read only one character; -r: raw input (disable backslash escaping)
  read -p "  Continue with this subscription? (y/n) " -n 1 -r; echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Deployment cancelled."; exit 0; }
  echo ""
}

register_providers() {
  # PURPOSE: Register Azure resource providers needed for AKS, networking, and monitoring
  # Azure requires explicit provider registration before creating resources; this is a one-time per subscription
  echo -e "${YELLOW}[3/5] Registering resource providers...${NC}"

  # Loop through three critical providers:
  # 1. Microsoft.ContainerService - for AKS cluster operations
  # 2. Microsoft.OperationalInsights - for Log Analytics workspace (monitoring)
  # 3. Microsoft.Network - for VNet, public IP, load balancer resources
  for provider in Microsoft.ContainerService Microsoft.OperationalInsights Microsoft.Network; do
    echo "  Registering $provider..."
    # --wait: block until registration completes (can take 30-60 seconds per provider)
    # --output none: suppress JSON response for cleaner output
    az provider register --namespace "$provider" --wait --output none
  done

  echo -e "${GREEN}  ✓ All providers registered${NC}"
  echo ""
}

create_resource_group() {
  # PURPOSE: Create or verify Azure resource group where all infrastructure will be deployed
  # Resource groups are logical containers for related Azure resources
  echo -e "${YELLOW}[4/5] Creating resource group...${NC}"

  # Check if resource group already exists
  # 'az group exists' outputs JSON: { "exists": true/false }
  # grep looks for "true" in output; if found, group already exists
  if az group exists --name "$RESOURCE_GROUP" | grep -q true; then
    echo -e "${GREEN}  ✓ Resource group '$RESOURCE_GROUP' already exists${NC}"
  else
    # Create new resource group in specified location
    # --output none: suppress verbose JSON response
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    echo -e "${GREEN}  ✓ Resource group '$RESOURCE_GROUP' created in '$LOCATION'${NC}"
  fi
  echo ""
}

deploy_infrastructure() {
  # PURPOSE: Deploy all Azure infrastructure (AKS cluster, VNet, Log Analytics) using Bicep template
  # This is the main deployment that takes 5-10 minutes to complete
  echo -e "${YELLOW}[5/5] Deploying AKS host cluster via Bicep...${NC}"
  echo "  This takes ~5-10 minutes..."
  echo ""

  # az deployment group create: Execute a resource template deployment at resource group scope
  # --name: unique deployment name (includes timestamp to prevent conflicts)
  # --resource-group: target resource group where resources will be created
  # --template-file: path to main.bicep (Infrastructure-as-Code template)
  # --parameters: path to main.bicepparam (parameter file with customizations)
  # --output table: format output as readable table instead of JSON
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
  # PURPOSE: Extract the AKS cluster name from deployment outputs and configure kubectl
  # This allows kubectl/helm to communicate with the newly created AKS cluster
  
  # Retrieve AKS cluster name from Bicep deployment outputs
  # az deployment group show: fetch information about a completed deployment
  # --query: extract specific JSON path (outputs.aksClusterName.value)
  # -o tsv: output as tab-separated values (just the value, no key names)
  local cluster_name
  cluster_name=$(az deployment group show \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query properties.outputs.aksClusterName.value -o tsv)

  echo ""
  echo -e "${YELLOW}Getting AKS credentials...${NC}"
  
  # az aks get-credentials: download cluster credentials and merge into ~/.kube/config
  # This command:
  #   - Authenticates against Azure using current login
  #   - Downloads kubeconfig for the AKS cluster
  #   - Merges it with existing kubeconfig entries
  # --overwrite-existing: replace old credentials if they already exist for this cluster
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
