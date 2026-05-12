#!/bin/bash
# ========================================
# Cleanup Script for Falco AKS Demo
# ========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
DEPLOYMENT_NAME="main-subscription"
PARAM_FILE="../main-subscription.bicepparam"
AKS_CLUSTER_NAMES=""

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

resolve_resource_group() {
    # Prefer caller-supplied env var
    if [ -n "$RESOURCE_GROUP" ]; then
        return
    fi

    # Try the recorded deployment outputs first (single source of truth)
    if command -v az >/dev/null 2>&1; then
        local rg
        rg=$(az deployment sub show --name "$DEPLOYMENT_NAME" \
            --query properties.outputs.resourceGroupName.value -o tsv 2>/dev/null || true)
        if [ -n "$rg" ] && [ "$rg" != "null" ]; then
            RESOURCE_GROUP="$rg"
            return
        fi
    fi

    # Fall back to parsing the bicepparam file used by deploy.sh
    if [ -f "$PARAM_FILE" ]; then
        local rg
        rg=$(grep -E "^[[:space:]]*param[[:space:]]+resourceGroupName" "$PARAM_FILE" \
            | head -n1 | sed -E "s/.*=[[:space:]]*'([^']+)'.*/\1/")
        if [ -n "$rg" ]; then
            RESOURCE_GROUP="$rg"
            return
        fi
    fi

    print_error "Could not determine resource group. Set RESOURCE_GROUP env var:"
    print_error "  RESOURCE_GROUP=rg-falco-demo-1 ./cleanup.sh"
    exit 1
}

confirm_deletion() {
    print_warning "This will delete the resource group: $RESOURCE_GROUP"
    print_warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_info "Cleanup cancelled."
        exit 0
    fi
}

cleanup_resources() {
    print_info "Starting cleanup process..."
    
    # Check if resource group exists
    if az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
        print_info "Deleting resource group: $RESOURCE_GROUP..."
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        print_info "Resource group deletion initiated."
        print_info "Note: Deletion may take several minutes to complete."
    else
        print_warning "Resource group $RESOURCE_GROUP does not exist."
    fi
}

discover_aks_clusters() {
    AKS_CLUSTER_NAMES=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
}

cleanup_aks_contexts() {
    if ! command -v kubectl >/dev/null 2>&1; then
        return
    fi

    if [ -z "$AKS_CLUSTER_NAMES" ]; then
        print_info "No AKS clusters found for kubeconfig cleanup."
        return
    fi

    print_info "Removing AKS kubeconfig entries..."
    while IFS= read -r cluster; do
        [ -z "$cluster" ] && continue
        kubectl config delete-context "$cluster" 2>/dev/null || true
        kubectl config delete-cluster "$cluster" 2>/dev/null || true
        kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${cluster}" 2>/dev/null || true
        kubectl config delete-user "clusterAdmin_${RESOURCE_GROUP}_${cluster}" 2>/dev/null || true
        print_info "Removed kubeconfig entries for: $cluster"
    done <<< "$AKS_CLUSTER_NAMES"
}

# Main execution
main() {
    print_info "Falco AKS Demo Cleanup"
    print_info "======================"
    echo ""
    
    confirm_deletion
    discover_aks_clusters
    cleanup_resources
    cleanup_aks_contexts
    
    print_info "\nCleanup completed!"
}

# Resolve target resource group dynamically before prompting
resolve_target() {
    resolve_resource_group
}

# Run main function
resolve_target
main
