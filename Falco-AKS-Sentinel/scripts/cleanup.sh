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
RESOURCE_GROUP="rg-falco-demo"

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

# Main execution
main() {
    print_info "Falco AKS Demo Cleanup"
    print_info "======================"
    echo ""
    
    confirm_deletion
    cleanup_resources
    
    print_info "\nCleanup completed!"
}

# Run main function
main
