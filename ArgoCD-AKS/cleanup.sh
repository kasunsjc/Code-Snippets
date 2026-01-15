#!/bin/bash

# ArgoCD on AKS - Cleanup Script
# This script removes ArgoCD and deletes the Azure infrastructure

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ARGOCD_NAMESPACE="argocd"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}ArgoCD on AKS Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Ask for confirmation
read -p "This will delete all ArgoCD resources and Azure infrastructure. Are you sure? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_status "Cleanup cancelled."
    exit 0
fi

# Get resource group name from deployment
print_status "Finding resource group..."
RG_NAME=$(az deployment sub list \
    --query "[?contains(name, 'argocd-aks-deployment')].{name:name, timestamp:properties.timestamp} | sort_by(@, &timestamp) | [-1].name" -o tsv 2>/dev/null | \
    xargs -I {} az deployment sub show --name {} --query 'properties.outputs.resourceGroupName.value' -o tsv 2>/dev/null || echo "")

if [ -z "$RG_NAME" ]; then
    print_warning "Could not find resource group from deployment outputs."
    read -p "Enter resource group name manually (or press Enter to skip): " RG_NAME
fi

# Uninstall ArgoCD if kubectl is configured
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    print_status "Checking for ArgoCD installation..."
    
    if kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
        print_status "Uninstalling ArgoCD..."
        
        # Delete all ArgoCD applications first
        print_status "Deleting ArgoCD applications..."
        kubectl delete applications --all -n "$ARGOCD_NAMESPACE" --timeout=60s 2>/dev/null || true
        
        # Uninstall Helm release
        if command -v helm &> /dev/null; then
            print_status "Removing ArgoCD Helm release..."
            helm uninstall argocd -n "$ARGOCD_NAMESPACE" --wait --timeout 5m 2>/dev/null || true
        fi
        
        # Delete namespace
        print_status "Deleting ArgoCD namespace..."
        kubectl delete namespace "$ARGOCD_NAMESPACE" --timeout=120s 2>/dev/null || true
        
        print_status "ArgoCD uninstalled successfully."
    else
        print_warning "ArgoCD namespace not found. Skipping ArgoCD cleanup."
    fi
else
    print_warning "kubectl not configured or cluster not accessible. Skipping ArgoCD cleanup."
fi

# Delete Azure resources
if [ -n "$RG_NAME" ]; then
    print_status "Deleting resource group: $RG_NAME"
    
    # Check if resource group exists
    if az group exists --name "$RG_NAME" | grep -q "true"; then
        print_warning "This will delete all resources in the resource group: $RG_NAME"
        read -p "Continue? (yes/no): " -r
        echo
        
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            az group delete \
                --name "$RG_NAME" \
                --yes \
                --no-wait
            
            print_status "Resource group deletion initiated (running in background)."
            print_status "You can check the status with: az group show --name $RG_NAME"
        else
            print_status "Resource group deletion cancelled."
        fi
    else
        print_warning "Resource group $RG_NAME does not exist."
    fi
else
    print_warning "No resource group to delete."
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Process Initiated${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
print_status "ArgoCD has been removed from the cluster."
print_status "Azure resource deletion is running in the background."
echo ""
