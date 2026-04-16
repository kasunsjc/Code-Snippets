#!/bin/bash
set -euo pipefail

# ============================================================
# Cleanup AKS Blue-Green Node Pool Demo
# ============================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="aks-bluegreen-demo"
CLUSTER_NAME="aks-bluegreen-cluster"

# Functions
print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

confirm_deletion() {
    echo ""
    print_warning "This will delete the resource group: $RESOURCE_GROUP"
    print_warning "All resources in this group will be permanently deleted!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation

    if [ "$confirmation" != "yes" ]; then
        print_message "Cleanup cancelled."
        exit 0
    fi
}

abort_active_upgrades() {
    print_message "Checking for active blue-green upgrades..."

    PROVISIONING_STATE=$(az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name userpool \
        --query provisioningState \
        --output tsv 2>/dev/null || echo "NotFound")

    if [ "$PROVISIONING_STATE" = "Upgrading" ]; then
        print_warning "Active upgrade detected. Aborting..."
        az aks nodepool operation-abort \
            --name userpool \
            --cluster-name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" 2>/dev/null || true
        print_message "Upgrade aborted."
    else
        print_message "No active upgrades to abort."
    fi
}

remove_kubectl_context() {
    print_message "Removing kubectl context..."

    kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null \
        && echo "  Deleted context: $CLUSTER_NAME" \
        || echo "  Context not found, skipping."

    kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null \
        && echo "  Deleted cluster: $CLUSTER_NAME" \
        || echo "  Cluster entry not found, skipping."

    kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" 2>/dev/null \
        && echo "  Deleted user: clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" \
        || echo "  User entry not found, skipping."

    print_message "Kubectl context cleanup done!"
}

delete_resource_group() {
    print_message "Deleting resource group: $RESOURCE_GROUP..."
    print_warning "This may take several minutes..."

    if az group exists --name "$RESOURCE_GROUP" | grep -q true; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait

        print_message "Resource group deletion initiated!"
    else
        print_warning "Resource group $RESOURCE_GROUP does not exist."
    fi
}

# Main execution
main() {
    print_message "Starting AKS Blue-Green Node Pool demo cleanup..."

    confirm_deletion
    abort_active_upgrades
    remove_kubectl_context
    delete_resource_group

    echo ""
    print_message "Cleanup completed successfully!"
    print_message "Resource group deletion is running in the background."
    print_message "Run 'az group show -n $RESOURCE_GROUP' to check status."
    echo ""
}

main
