#!/bin/bash

# Script to deploy sample applications with issues

set -e

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
echo "=========================================="
echo "  Deploying Troubleshooting Demo Apps"
echo "=========================================="
echo ""

print_message "Creating namespace..."
kubectl apply -f 00-namespace.yaml

print_message "Deploying applications with issues..."
kubectl apply -f 01-crashloop-app.yaml
kubectl apply -f 02-oomkilled-app.yaml
kubectl apply -f 03-imagepull-error.yaml
kubectl apply -f 04-pending-pod.yaml
kubectl apply -f 05-liveness-failure.yaml
kubectl apply -f 06-network-policy-block.yaml
kubectl apply -f 07-configmap-missing.yaml
kubectl apply -f 08-init-container-failure.yaml
kubectl apply -f 09-resource-issues.yaml

echo ""
print_message "Deployment complete! Waiting for issues to manifest..."
sleep 5

echo ""
echo "=========================================="
echo "  Current Pod Status"
echo "=========================================="
kubectl get pods -n troubleshooting-demos

echo ""
echo "=========================================="
echo "  Try These Queries with Agentic CLI"
echo "=========================================="
echo ""
echo "1. General health check:"
echo "   az aks agent \"What issues exist in the troubleshooting-demos namespace?\""
echo ""
echo "2. Specific pod investigation:"
echo "   az aks agent \"Why is the crashloop-app pod failing?\""
echo ""
echo "3. Resource issues:"
echo "   az aks agent \"Which pods are pending and why?\""
echo ""
echo "4. Memory problems:"
echo "   az aks agent \"Why is oomkilled-app restarting?\""
echo ""
echo "5. Network debugging:"
echo "   az aks agent \"Can frontend-app reach backend-service?\""
echo ""
echo "6. Configuration issues:"
echo "   az aks agent \"What's wrong with configmap-missing-app?\""
echo ""
echo "=========================================="
echo ""
