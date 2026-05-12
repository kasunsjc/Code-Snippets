#!/bin/bash

# Cleanup script for Agentic CLI AKS Demo
# This script removes all deployed resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
RESOURCE_GROUP_NAME="rg-aksagent-demo"

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

confirm_deletion() {
    echo ""
    print_warning "This will delete the resource group: $RESOURCE_GROUP_NAME"
    print_warning "All resources in this group will be permanently deleted!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_message "Cleanup cancelled."
        exit 0
    fi
}

delete_resource_group() {
    print_message "Deleting resource group: $RESOURCE_GROUP_NAME..."
    print_warning "This may take several minutes..."
    
    if az group exists --name "$RESOURCE_GROUP_NAME" | grep -q true; then
        az group delete \
            --name "$RESOURCE_GROUP_NAME" \
            --yes \
            --no-wait
        
        print_message "Resource group deletion initiated!"
        print_message "You can check the deletion status in Azure Portal."
    else
        print_warning "Resource group $RESOURCE_GROUP_NAME does not exist."
    fi
}

remove_kubectl_context() {
    print_message "Removing AKS kubeconfig entries..."

    local cluster_names
    cluster_names=$(az aks list --resource-group "$RESOURCE_GROUP_NAME" --query "[].name" -o tsv 2>/dev/null || true)

    if [ -z "$cluster_names" ]; then
        print_message "No AKS clusters found in resource group."
        return
    fi

    while IFS= read -r cluster; do
        [ -z "$cluster" ] && continue
        kubectl config delete-context "$cluster" 2>/dev/null || true
        kubectl config delete-cluster "$cluster" 2>/dev/null || true
        kubectl config delete-user "clusterUser_${RESOURCE_GROUP_NAME}_${cluster}" 2>/dev/null || true
        kubectl config delete-user "clusterAdmin_${RESOURCE_GROUP_NAME}_${cluster}" 2>/dev/null || true
        print_message "Removed kubeconfig entries for: $cluster"
    done <<< "$cluster_names"
}

# Main execution
main() {
    print_message "Starting cleanup process..."
    
    confirm_deletion
    delete_resource_group
    remove_kubectl_context
    
    print_message "Cleanup completed successfully!"
    echo ""
    print_message "Note: Resource deletion may take several minutes to complete."
    print_message "You can verify deletion in Azure Portal or run: az group show --name $RESOURCE_GROUP_NAME"
    echo ""
}

# Run main function
main
