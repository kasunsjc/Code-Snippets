#!/bin/bash

# Cleanup all sample apps and network policies

set -e

GREEN='\033[0;32m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

echo ""
echo "=========================================="
echo "   Cleanup Cilium Demo Sample Apps"
echo "=========================================="
echo ""

print_message "Deleting cilium-demo namespace and all resources..."
kubectl delete namespace cilium-demo --ignore-not-found

print_message "Removing cluster-wide network policy..."
kubectl delete ciliumclusterwidenetworkpolicy default-deny-ingress --ignore-not-found

print_message "Cleanup complete!"
