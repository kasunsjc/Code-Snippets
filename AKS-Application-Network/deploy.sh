#!/bin/bash
# Azure Kubernetes Application Network Demo - Deployment Script
# Deploys an AKS cluster and joins it to an Azure Kubernetes Application Network
#
# Prerequisites:
#   - Azure CLI 2.84.0+
#   - Bicep CLI (installed via: az bicep install)
#   - kubectl
#
# Documentation: https://learn.microsoft.com/en-us/azure/application-network/get-started

set -e

# ---------------------------------------------------------------------------
# Color codes
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Configuration - edit these values or export before running
# ---------------------------------------------------------------------------
LOCATION="${LOCATION:-eastus}"
ENVIRONMENT="${ENVIRONMENT:-demo}"
AKS_RG="${AKS_RG:-rg-appnet-${ENVIRONMENT}}"
APPNET_RG="${APPNET_RG:-rg-appnet-resource-${ENVIRONMENT}}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-appnet-${ENVIRONMENT}}"
APPNET_NAME="${APPNET_NAME:-appnet-${ENVIRONMENT}}"
APPNET_MEMBER_NAME="${APPNET_MEMBER_NAME:-member-${CLUSTER_NAME}}"
DEPLOYMENT_NAME="appnet-deployment-$(date +%s)"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

check_prereqs() {
    log_section "Checking Prerequisites"

    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi

    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${AZ_VERSION}"

    az account show &> /dev/null || {
        log_error "Not logged in. Run: az login"
        exit 1
    }

    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl not found. Install it or use: az aks install-cli"
    fi

    log_info "Prerequisites check passed"
}

confirm_subscription() {
    log_section "Subscription Confirmation"

    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    echo "  Subscription : ${SUBSCRIPTION_NAME}"
    echo "  ID           : ${SUBSCRIPTION_ID}"
    echo "  Location     : ${LOCATION}"
    echo "  Environment  : ${ENVIRONMENT}"
    echo ""

    read -p "Continue with this subscription? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled."
        exit 0
    fi

    SUBSCRIPTION="${SUBSCRIPTION_ID}"
}

register_feature() {
    log_section "Registering Preview Feature & Resource Provider"

    log_info "Registering Microsoft.AppLink/PublicPreview feature..."
    az feature register \
        --namespace Microsoft.AppLink \
        --name PublicPreview \
        --subscription "${SUBSCRIPTION}"

    log_info "Waiting for feature registration (this may take a few minutes)..."
    while true; do
        FEATURE_STATE=$(az feature show \
            --namespace Microsoft.AppLink \
            --name PublicPreview \
            --subscription "${SUBSCRIPTION}" \
            --query properties.state -o tsv)
        if [[ "${FEATURE_STATE}" == "Registered" ]]; then
            log_info "Feature registered successfully."
            break
        fi
        log_warn "Feature state: ${FEATURE_STATE} - waiting 15s..."
        sleep 15
    done

    log_info "Refreshing Microsoft.AppLink resource provider..."
    az provider register --namespace Microsoft.AppLink --subscription "${SUBSCRIPTION}"

    log_info "Registering Microsoft.ContainerService resource provider..."
    az provider register --namespace Microsoft.ContainerService --wait

    log_info "Resource provider registration complete."
}

install_appnet_extension() {
    log_section "Installing AppNet CLI Extension"

    if az extension show --name appnet-preview &> /dev/null; then
        log_info "appnet-preview extension already installed. Updating..."
        az extension update --name appnet-preview
    else
        log_info "Installing appnet-preview extension..."
        az extension add --name appnet-preview
    fi

    log_info "AppNet CLI extension ready."
}

deploy_infrastructure() {
    log_section "Deploying AKS Infrastructure (Bicep)"

    log_info "Validating Bicep template..."
    az deployment sub validate \
        --location "${LOCATION}" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --name "${DEPLOYMENT_NAME}-validate"

    log_info "Deploying AKS cluster and resource groups..."
    az deployment sub create \
        --location "${LOCATION}" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --name "${DEPLOYMENT_NAME}"

    log_info "Bicep deployment complete."
}

enable_gateway_api() {
    log_section "Enabling Managed Kubernetes Gateway API"

    # Gateway API must be enabled on the cluster (required for Application Network)
    log_info "Enabling Gateway API add-on on cluster ${CLUSTER_NAME}..."
    az aks update \
        --name "${CLUSTER_NAME}" \
        --resource-group "${AKS_RG}" \
        --enable-gateway-api

    log_info "Gateway API enabled."
}

grant_cluster_access() {
    log_section "Granting Cluster Access (Azure RBAC)"

    # Get current user's object ID (required for Azure RBAC on AKS with Entra ID)
    log_info "Getting current user identity..."
    CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
    
    if [[ -z "${CURRENT_USER_ID}" ]]; then
        log_warn "Could not determine current user ID. Trying alternative method..."
        CURRENT_USER_EMAIL=$(az account show --query user.name -o tsv)
        CURRENT_USER_ID=$(az ad user show --id "${CURRENT_USER_EMAIL}" --query id -o tsv 2>/dev/null || true)
    fi

    if [[ -z "${CURRENT_USER_ID}" ]]; then
        log_error "Failed to get current user object ID. You may need to manually grant cluster access."
        log_info "Run this command manually:"
        log_info "az role assignment create --role 'Azure Kubernetes Service RBAC Cluster Admin' --assignee YOUR_USER_EMAIL --scope \$(az aks show -g ${AKS_RG} -n ${CLUSTER_NAME} --query id -o tsv)"
        return 1
    fi

    # Get AKS cluster resource ID
    CLUSTER_RESOURCE_ID=$(az aks show \
        --name "${CLUSTER_NAME}" \
        --resource-group "${AKS_RG}" \
        --query id -o tsv)

    log_info "Granting 'Azure Kubernetes Service RBAC Cluster Admin' to current user..."
    az role assignment create \
        --role "Azure Kubernetes Service RBAC Cluster Admin" \
        --assignee "${CURRENT_USER_ID}" \
        --scope "${CLUSTER_RESOURCE_ID}" \
        2>/dev/null || log_warn "Role assignment may already exist (this is normal)."

    log_info "Cluster access granted. Waiting 120s for RBAC propagation (Azure RBAC can take 2-5 minutes)..."
    sleep 120
    
    log_info "RBAC propagation wait complete. Proceeding with kubectl operations..."
}

create_appnet_resource() {
    log_section "Creating Azure Kubernetes Application Network Resource"

    log_info "Creating AppNet resource group: ${APPNET_RG}..."
    az group create --name "${APPNET_RG}" --location "${LOCATION}"

    log_info "Creating Application Network resource: ${APPNET_NAME}..."
    az appnet create \
        --resource-group "${APPNET_RG}" \
        --name "${APPNET_NAME}" \
        --location "${LOCATION}" \
        --identity-type SystemAssigned

    log_info "Application Network resource created."
    az appnet show --resource-group "${APPNET_RG}" --name "${APPNET_NAME}"
}

join_cluster_to_appnet() {
    log_section "Joining AKS Cluster to Application Network"

    CLUSTER_RESOURCE_ID=$(az aks show \
        --name "${CLUSTER_NAME}" \
        --resource-group "${AKS_RG}" \
        --query id -o tsv)

    log_info "Joining cluster as member '${APPNET_MEMBER_NAME}' (SelfManaged upgrade mode)..."
    az appnet member join \
        --resource-group "${APPNET_RG}" \
        --appnet-name "${APPNET_NAME}" \
        --member-name "${APPNET_MEMBER_NAME}" \
        --member-resource-id "${CLUSTER_RESOURCE_ID}" \
        --upgrade-mode SelfManaged

    log_info "Waiting for member provisioning to complete..."
    while true; do
        PROVISIONING_STATE=$(az appnet member show \
            --resource-group "${APPNET_RG}" \
            --appnet-name "${APPNET_NAME}" \
            --member-name "${APPNET_MEMBER_NAME}" \
            --query properties.provisioningState -o tsv)
        if [[ "${PROVISIONING_STATE}" == "Succeeded" ]]; then
            log_info "Member provisioning succeeded."
            break
        elif [[ "${PROVISIONING_STATE}" == "Failed" ]]; then
            log_error "Member provisioning failed. Check the portal for details."
            exit 1
        fi
        log_warn "Provisioning state: ${PROVISIONING_STATE} - waiting 20s..."
        sleep 20
    done
}

configure_kubectl() {
    log_section "Configuring kubectl"

    log_info "Getting AKS credentials..."
    az aks get-credentials \
        --name "${CLUSTER_NAME}" \
        --resource-group "${AKS_RG}" \
        --overwrite-existing

    log_info "Verifying cluster connectivity..."
    kubectl get nodes
    kubectl get namespaces
}

deploy_sample_apps() {
    log_section "Deploying Sample Applications"

    log_info "Creating demo namespace and labeling for ambient mesh..."
    kubectl apply -f sample-apps/namespace.yaml

    log_info "Deploying HTTPBin service..."
    kubectl apply -f sample-apps/httpbin.yaml

    log_info "Deploying Sleep client..."
    kubectl apply -f sample-apps/sleep.yaml

    log_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=Ready pod -l app=httpbin -n demo --timeout=120s
    kubectl wait --for=condition=Ready pod -l app=sleep -n demo --timeout=120s

    log_info "Sample applications deployed."
}

print_summary() {
    log_section "Deployment Summary"

    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo ""
    echo "  AKS Cluster        : ${CLUSTER_NAME}"
    echo "  AKS Resource Group : ${AKS_RG}"
    echo "  AppNet Name        : ${APPNET_NAME}"
    echo "  AppNet RG          : ${APPNET_RG}"
    echo "  Member Name        : ${APPNET_MEMBER_NAME}"
    echo ""
    echo "Useful commands:"
    echo "  List members       : az appnet member list --resource-group ${APPNET_RG} --appnet-name ${APPNET_NAME} --output table"
    echo "  Show member        : az appnet member show --resource-group ${APPNET_RG} --appnet-name ${APPNET_NAME} --member-name ${APPNET_MEMBER_NAME}"
    echo "  Get credentials    : az aks get-credentials --name ${CLUSTER_NAME} --resource-group ${AKS_RG}"
    echo ""
    echo "Next steps:"
    echo "  1. Apply waypoint proxy  : kubectl apply -f sample-apps/waypoint.yaml"
    echo "  2. Apply auth policies   : kubectl apply -f sample-apps/authorization-policy.yaml"
    echo "  3. Run commands.azcli for observability and L7 traffic management demos"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

log_section "Azure Kubernetes Application Network Demo"
log_info "Starting deployment..."

check_prereqs
confirm_subscription
register_feature
install_appnet_extension
deploy_infrastructure
enable_gateway_api
grant_cluster_access
create_appnet_resource
join_cluster_to_appnet
configure_kubectl
deploy_sample_apps
print_summary
