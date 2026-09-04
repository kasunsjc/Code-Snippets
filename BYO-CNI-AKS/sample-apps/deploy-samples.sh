#!/bin/bash

# Deploy all sample apps and network policies

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "=========================================="
echo "   Deploy Cilium Demo Sample Apps"
echo "=========================================="
echo ""

# Create namespace and deploy app
print_message "Creating namespace..."
kubectl apply -f "$SCRIPT_DIR/00-namespace.yaml"

print_message "Deploying sample 3-tier application..."
kubectl apply -f "$SCRIPT_DIR/01-sample-app.yaml"

print_message "Waiting for pods to be ready..."
kubectl -n cilium-demo wait --for=condition=ready pod --all --timeout=120s

print_message "Applying L3/L4 network policy (frontend -> backend)..."
kubectl apply -f "$SCRIPT_DIR/02-cilium-l3-l4-policy.yaml"

print_message "Applying database network policy (backend -> database)..."
kubectl apply -f "$SCRIPT_DIR/03-cilium-database-policy.yaml"

echo ""
print_message "Sample apps and basic network policies deployed!"
echo ""
print_warning "Additional policies available:"
echo "  04-cilium-l7-policy.yaml          - L7 HTTP-aware policy"
echo "  05-cilium-clusterwide-policy.yaml - Default deny ingress (cluster-wide, kube-system excluded)"
echo "  06-cilium-dns-egress-policy.yaml  - DNS-aware egress policy"
echo ""
echo "To use the L7 policy, delete the L3/L4 policy first (policies are additive,"
echo "so the broader L3/L4 allow would bypass the L7 restrictions):"
echo "  kubectl delete -f sample-apps/02-cilium-l3-l4-policy.yaml"
echo "  kubectl apply -f sample-apps/04-cilium-l7-policy.yaml"
echo ""

# Show status
print_message "Current pod status:"
kubectl -n cilium-demo get pods -o wide
echo ""
print_message "Current services:"
kubectl -n cilium-demo get svc
echo ""
print_message "Active Cilium Network Policies:"
kubectl -n cilium-demo get cnp
