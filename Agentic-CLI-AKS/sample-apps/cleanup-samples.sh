#!/bin/bash

# Script to clean up all sample applications

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

echo ""
print_warning "This will delete all troubleshooting demo applications"
read -p "Are you sure? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    print_message "Cleanup cancelled."
    exit 0
fi

echo ""
print_message "Deleting applications using manifest files..."

# Delete in reverse order to handle dependencies
kubectl delete -f 09-resource-issues.yaml --ignore-not-found=true
kubectl delete -f 08-init-container-failure.yaml --ignore-not-found=true
kubectl delete -f 07-configmap-missing.yaml --ignore-not-found=true
kubectl delete -f 06-network-policy-block.yaml --ignore-not-found=true
kubectl delete -f 05-liveness-failure.yaml --ignore-not-found=true
kubectl delete -f 04-pending-pod.yaml --ignore-not-found=true
kubectl delete -f 03-imagepull-error.yaml --ignore-not-found=true
kubectl delete -f 02-oomkilled-app.yaml --ignore-not-found=true
kubectl delete -f 01-crashloop-app.yaml --ignore-not-found=true

print_message "Deleting namespace..."
kubectl delete -f 00-namespace.yaml --ignore-not-found=true

print_message "Waiting for namespace deletion to complete..."
kubectl wait --for=delete namespace/troubleshooting-demos --timeout=60s 2>/dev/null || true

print_message "Cleanup complete!"
echo ""
