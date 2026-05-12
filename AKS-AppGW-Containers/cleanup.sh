#!/bin/bash

# Cleanup script for AKS with Application Gateway for Containers Demo

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

RESOURCE_GROUP_NAME="rg-agfc-demo"

cleanup_aks_contexts() {
    print_message "Removing AKS kubeconfig entries..."
    local cluster_names
    cluster_names=$(az aks list --resource-group "$RESOURCE_GROUP_NAME" --query "[].name" -o tsv 2>/dev/null || true)

    if [[ -z "$cluster_names" ]]; then
        print_message "No AKS clusters found in resource group."
        return
    fi

    while IFS= read -r cluster; do
        [[ -z "$cluster" ]] && continue
        kubectl config delete-context "$cluster" 2>/dev/null || true
        kubectl config delete-cluster "$cluster" 2>/dev/null || true
        kubectl config delete-user "clusterUser_${RESOURCE_GROUP_NAME}_${cluster}" 2>/dev/null || true
        kubectl config delete-user "clusterAdmin_${RESOURCE_GROUP_NAME}_${cluster}" 2>/dev/null || true
        print_message "Removed kubeconfig entries for: $cluster"
    done <<< "$cluster_names"
}

print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

echo ""
echo "=========================================="
echo "   AKS + AppGW for Containers - Cleanup"
echo "=========================================="
echo ""

print_warning "This will delete ALL resources in resource group: $RESOURCE_GROUP_NAME"
echo ""

read -p "Are you sure you want to continue? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Delete Kubernetes resources first (if cluster is still accessible)
print_message "Cleaning up Kubernetes resources..."
kubectl delete -f kubernetes-manifests/gateway-managed/ 2>/dev/null || true
kubectl delete -f kubernetes-manifests/gateway-byo/ 2>/dev/null || true
kubectl delete -f kubernetes-manifests/01-sample-apps.yaml 2>/dev/null || true
kubectl delete applicationloadbalancer alb-test -n alb-test-infra 2>/dev/null || true
kubectl delete namespace alb-test-infra 2>/dev/null || true
kubectl delete namespace test-infra 2>/dev/null || true

print_message "Waiting for ALB resources to be cleaned up..."
sleep 30

# Delete the resource group
print_message "Deleting resource group: ${RESOURCE_GROUP_NAME}..."
az group delete --name "${RESOURCE_GROUP_NAME}" --yes --no-wait

cleanup_aks_contexts

print_message "Cleanup initiated. Resource group deletion is running in the background."
echo ""
echo "Run the following command to check deletion status:"
echo "  az group show --name ${RESOURCE_GROUP_NAME} --query 'properties.provisioningState' -o tsv"
echo ""
