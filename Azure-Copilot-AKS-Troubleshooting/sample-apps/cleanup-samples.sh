#!/bin/bash

# Cleanup sample applications

set -e

GREEN='\033[0;32m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

echo ""
echo "=============================================="
echo "  Cleaning Up Troubleshooting Demo Apps"
echo "=============================================="
echo ""

print_message "Deleting namespace and all resources..."
kubectl delete namespace troubleshooting-demos --ignore-not-found

print_message "Cleanup complete!"
