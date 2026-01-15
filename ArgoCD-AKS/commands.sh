#!/bin/bash

# Quick commands for ArgoCD on AKS demo

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}ArgoCD on AKS - Quick Commands${NC}"
echo ""

# Variables - Update these based on your deployment
RG_NAME="rg-argocd-dev"
AKS_NAME="aks-argocd-dev"
ARGOCD_NAMESPACE="argocd"

echo -e "${YELLOW}=== Azure Commands ===${NC}"
echo ""

echo "# Get AKS credentials"
echo "az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME"
echo ""

echo "# Check AKS status"
echo "az aks show --resource-group $RG_NAME --name $AKS_NAME --query provisioningState -o tsv"
echo ""

echo "# Get AKS nodes"
echo "kubectl get nodes"
echo ""

echo -e "${YELLOW}=== ArgoCD Access ===${NC}"
echo ""

echo "# Get ArgoCD admin password"
echo "kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""

echo "# Get ArgoCD Server URL (LoadBalancer IP)"
echo "kubectl get svc argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
echo ""

echo "# Port forward to access ArgoCD UI locally"
echo "kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo "# Then access: https://localhost:8080"
echo ""

echo -e "${YELLOW}=== ArgoCD CLI ===${NC}"
echo ""

echo "# Login to ArgoCD (after port-forward)"
echo "argocd login localhost:8080 --username admin --insecure"
echo ""

echo "# List applications"
echo "argocd app list"
echo ""

echo "# Create application from Git"
echo "argocd app create myapp \\"
echo "  --repo https://github.com/argoproj/argocd-example-apps.git \\"
echo "  --path guestbook \\"
echo "  --dest-server https://kubernetes.default.svc \\"
echo "  --dest-namespace default"
echo ""

echo "# Sync application"
echo "argocd app sync myapp"
echo ""

echo "# Get application status"
echo "argocd app get myapp"
echo ""

echo "# Set auto-sync"
echo "argocd app set myapp --sync-policy automated"
echo ""

echo "# Delete application"
echo "argocd app delete myapp"
echo ""

echo -e "${YELLOW}=== Kubernetes Commands ===${NC}"
echo ""

echo "# Get all ArgoCD resources"
echo "kubectl get all -n $ARGOCD_NAMESPACE"
echo ""

echo "# Check ArgoCD pods"
echo "kubectl get pods -n $ARGOCD_NAMESPACE"
echo ""

echo "# View ArgoCD server logs"
echo "kubectl logs -n $ARGOCD_NAMESPACE deployment/argocd-server -f"
echo ""

echo "# View application controller logs"
echo "kubectl logs -n $ARGOCD_NAMESPACE deployment/argocd-application-controller -f"
echo ""

echo "# Get ArgoCD Applications"
echo "kubectl get applications -n $ARGOCD_NAMESPACE"
echo ""

echo "# Describe an application"
echo "kubectl describe application myapp -n $ARGOCD_NAMESPACE"
echo ""

echo -e "${YELLOW}=== Monitoring ===${NC}"
echo ""

echo "# Check ArgoCD metrics"
echo "kubectl port-forward svc/argocd-metrics -n $ARGOCD_NAMESPACE 8082:8082"
echo "# Access metrics at: http://localhost:8082/metrics"
echo ""

echo "# Check repo server metrics"
echo "kubectl port-forward svc/argocd-repo-server -n $ARGOCD_NAMESPACE 8084:8084"
echo ""

echo -e "${YELLOW}=== Troubleshooting ===${NC}"
echo ""

echo "# Check all events in ArgoCD namespace"
echo "kubectl get events -n $ARGOCD_NAMESPACE --sort-by='.lastTimestamp'"
echo ""

echo "# Restart ArgoCD server"
echo "kubectl rollout restart deployment/argocd-server -n $ARGOCD_NAMESPACE"
echo ""

echo "# Check ArgoCD version"
echo "kubectl get deployment argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}'"
echo ""

echo "# Reset admin password"
echo "argocd account update-password"
echo ""

echo -e "${YELLOW}=== Sample Applications ===${NC}"
echo ""

echo "# Deploy simple nginx app"
echo "kubectl apply -f sample-apps/01-simple-app.yaml"
echo ""

echo "# Deploy ArgoCD Application"
echo "kubectl apply -f sample-apps/02-argocd-application.yaml"
echo ""

echo "# Deploy Helm application"
echo "kubectl apply -f sample-apps/03-helm-application.yaml"
echo ""

echo "# Deploy Kustomize application"
echo "kubectl apply -f sample-apps/04-kustomize-application.yaml"
echo ""

echo -e "${GREEN}Run any of these commands as needed!${NC}"
