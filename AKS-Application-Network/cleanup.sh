#!/bin/bash
# Azure Kubernetes Application Network Demo - Cleanup Script
# Removes all resources created by deploy.sh
#
# WARNING: This will permanently delete the AKS cluster and Application Network resource.

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
# Configuration - must match deploy.sh values
# ---------------------------------------------------------------------------
ENVIRONMENT="${ENVIRONMENT:-demo}"
AKS_RG="${AKS_RG:-rg-appnet-${ENVIRONMENT}}"
APPNET_RG="${APPNET_RG:-rg-appnet-resource-${ENVIRONMENT}}"
APPNET_NAME="${APPNET_NAME:-appnet-${ENVIRONMENT}}"
APPNET_MEMBER_NAME="${APPNET_MEMBER_NAME:-member-aks-appnet-${ENVIRONMENT}}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-appnet-${ENVIRONMENT}}"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log_section "Azure Kubernetes Application Network Demo - Cleanup"

echo -e "${RED}WARNING: This will delete the following resources:${NC}"
echo "  AKS Resource Group   : ${AKS_RG}"
echo "  AppNet Resource Group: ${APPNET_RG}"
echo "  AppNet Member        : ${APPNET_MEMBER_NAME}"
echo ""
read -p "Are you sure you want to delete all demo resources? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Cleanup cancelled."
    exit 0
fi

# Step 1: Remove the cluster from the Application Network before deleting anything
log_section "Step 1: Removing Cluster from Application Network"

if az appnet member show \
    --resource-group "${APPNET_RG}" \
    --appnet-name "${APPNET_NAME}" \
    --member-name "${APPNET_MEMBER_NAME}" &> /dev/null; then

    log_warn "Before removing the member, ensure all Istio ambient labels have been removed from workloads."
    log_info "Removing Istio ambient labels from namespace 'demo' (if present)..."
    if kubectl get namespace demo &> /dev/null; then
        kubectl label namespace demo istio.io/dataplane-mode- istio.io/use-waypoint- istio.io/use-waypoint-namespace- --overwrite 2>/dev/null || true
    fi

    log_info "Removing member '${APPNET_MEMBER_NAME}' from Application Network..."
    az appnet member remove \
        --resource-group "${APPNET_RG}" \
        --appnet-name "${APPNET_NAME}" \
        --member-name "${APPNET_MEMBER_NAME}"

    log_info "Waiting for member removal to complete..."
    while az appnet member show \
        --resource-group "${APPNET_RG}" \
        --appnet-name "${APPNET_NAME}" \
        --member-name "${APPNET_MEMBER_NAME}" &> /dev/null; do
        log_warn "Member still exists, waiting 15s..."
        sleep 15
    done
    log_info "Member removed."
else
    log_warn "Member '${APPNET_MEMBER_NAME}' not found. Skipping member removal."
fi

# Step 2: Delete the Application Network resource
log_section "Step 2: Deleting Application Network Resource"

if az appnet show --resource-group "${APPNET_RG}" --name "${APPNET_NAME}" &> /dev/null; then
    log_info "Deleting Application Network resource '${APPNET_NAME}'..."
    az appnet delete \
        --resource-group "${APPNET_RG}" \
        --name "${APPNET_NAME}" \
        --yes
    log_info "Application Network resource deleted."
else
    log_warn "Application Network resource '${APPNET_NAME}' not found. Skipping."
fi

# Step 3: Delete the AppNet resource group
log_section "Step 3: Deleting AppNet Resource Group"

if az group exists --name "${APPNET_RG}" | grep -q true; then
    log_info "Deleting resource group '${APPNET_RG}'..."
    az group delete --name "${APPNET_RG}" --yes --no-wait
    log_info "Resource group deletion initiated (running in background)."
else
    log_warn "Resource group '${APPNET_RG}' not found. Skipping."
fi

# Step 4: Delete the AKS resource group (includes cluster and node RG)
log_section "Step 4: Deleting AKS Resource Group"

if az group exists --name "${AKS_RG}" | grep -q true; then
    log_info "Deleting resource group '${AKS_RG}'..."
    az group delete --name "${AKS_RG}" --yes --no-wait
    log_info "Resource group deletion initiated (running in background)."
else
    log_warn "Resource group '${AKS_RG}' not found. Skipping."
fi

log_section "Cleanup Complete"
log_info "All resources have been scheduled for deletion."
log_info "Run the following to confirm deletion:"
echo "  az group exists --name ${AKS_RG}"
echo "  az group exists --name ${APPNET_RG}"
