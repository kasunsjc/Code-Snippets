#!/bin/bash

# Deploy sample applications with intentional issues for Copilot troubleshooting

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
echo "=============================================="
echo "  Deploying Copilot Troubleshooting Demo Apps"
echo "=============================================="
echo ""

print_message "Creating namespace..."
kubectl apply -f 00-namespace.yaml

print_message "Deploying applications with issues..."
kubectl apply -f 01-crashloop-app.yaml
kubectl apply -f 02-oom-killed-app.yaml
kubectl apply -f 03-image-pull-error.yaml
kubectl apply -f 04-pending-pod.yaml
kubectl apply -f 05-failing-probe-app.yaml
kubectl apply -f 06-dns-resolution-app.yaml
kubectl apply -f 07-wrong-port-app.yaml
kubectl apply -f 08-readonly-fs-app.yaml

echo ""
print_message "All apps deployed! Waiting for issues to manifest..."
sleep 10

echo ""
echo "=============================================="
echo "  Current Pod Status"
echo "=============================================="
kubectl get pods -n troubleshooting-demos -o wide

echo ""
echo "=============================================="
echo "  Next Steps"
echo "=============================================="
echo ""
echo "  1. Open the Azure Portal: https://portal.azure.com"
echo "  2. Navigate to your AKS cluster"
echo "  3. Click the Copilot icon in the top toolbar"
echo "  4. Try these prompts:"
echo ""
echo "     - Why are pods failing in the troubleshooting-demos namespace?"
echo "     - What is causing the CrashLoopBackOff for crashloop-app?"
echo "     - Why is oom-killed-app being OOMKilled?"
echo "     - Why is pending-pod stuck in Pending state?"
echo ""
