#!/bin/bash

# ==============================================================================
# ArgoCD on AKS - Deployment Script
# ==============================================================================
# This script automates the complete deployment of ArgoCD on Azure Kubernetes
# Service (AKS) with the following components:
#
# Infrastructure (via Bicep):
#   - Azure Kubernetes Service (AKS) cluster with Azure CNI networking
#   - Azure Monitor Workspace for managed Prometheus
#   - Azure Managed Grafana with pre-configured dashboards
#   - Virtual Network with proper subnet sizing
#   - Log Analytics workspace for AKS monitoring
#
# Kubernetes Components:
#   - cert-manager for automatic TLS certificate management
#   - Traefik ingress controller for external access
#   - ArgoCD in high-availability mode with Redis HA
#   - ServiceMonitors for Prometheus metrics collection
#
# Prerequisites:
#   - Azure CLI (az) installed and configured
#   - kubectl installed
#   - Helm 3 installed
#   - Appropriate Azure subscription permissions
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# Configuration and Color Codes
# ------------------------------------------------------------------------------
# ANSI color codes for formatted console output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Deployment configuration - modify these as needed
SUBSCRIPTION_NAME=""                          # Leave empty to use current subscription
DEPLOYMENT_NAME="argocd-aks-deployment"       # Base name for Azure deployment
BICEP_FILE="main.bicep"                       # Main Bicep template file
PARAMS_FILE="main.bicepparam"                 # Bicep parameters file

# Kubernetes namespaces
ARGOCD_NAMESPACE="argocd"                     # Namespace for ArgoCD components
CERT_MANAGER_NAMESPACE="cert-manager"         # Namespace for cert-manager
TRAEFIK_NAMESPACE="traefik"                   # Namespace for Traefik ingress

# Helm chart versions - update these to match your requirements
ARGOCD_VERSION="7.7.5"                        # ArgoCD Helm chart version
CERT_MANAGER_VERSION="1.16.2"                 # cert-manager Helm chart version
TRAEFIK_VERSION="33.0.0"                      # Traefik Helm chart version

# Domain configuration
ARGOCD_DOMAIN="argo-demo.kasunrajapakse.xyz"  # Your custom domain for ArgoCD

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ArgoCD on AKS Deployment${NC}"
echo -e "${GREEN}========================================${NC}"

# ------------------------------------------------------------------------------
# Helper Functions for Console Output
# ------------------------------------------------------------------------------
# These functions provide consistent, color-coded console output throughout
# the deployment process for better readability and user experience

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# ------------------------------------------------------------------------------
# Prerequisites Check
# ------------------------------------------------------------------------------
# Verify that all required CLI tools are installed before proceeding
# This prevents deployment failures due to missing dependencies

print_status "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install it first."
    exit 1
fi

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please install it first."
    exit 1
fi

print_status "All prerequisites satisfied"

# ------------------------------------------------------------------------------
# Azure Authentication and Subscription Setup
# ------------------------------------------------------------------------------
# Ensure user is logged into Azure and using the correct subscription

# Login to Azure (if not already logged in)
print_status "Checking Azure login status..."
az account show &> /dev/null || {
    print_status "Logging in to Azure..."
    az login
}

# Set subscription if specified in configuration
if [ -n "$SUBSCRIPTION_NAME" ]; then
    print_status "Setting subscription to: $SUBSCRIPTION_NAME"
    az account set --subscription "$SUBSCRIPTION_NAME"
fi

CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
print_status "Using subscription: $CURRENT_SUBSCRIPTION"

# ------------------------------------------------------------------------------
# Get Current User Identity for Grafana Access
# ------------------------------------------------------------------------------
# Retrieve the current user's Azure AD object ID to grant admin access to
# the Azure Managed Grafana instance. This allows the user to access Grafana
# dashboards immediately after deployment without manual role assignment

print_status "Getting current user object ID..."
CURRENT_USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")

if [ -n "$CURRENT_USER_OBJECT_ID" ]; then
    CURRENT_USER_EMAIL=$(az ad signed-in-user show --query userPrincipalName -o tsv)
    print_status "Current user: $CURRENT_USER_EMAIL"
else
    print_warning "Could not retrieve current user object ID. Grafana role assignment will be skipped."
fi

# ------------------------------------------------------------------------------
# Deploy Azure Infrastructure with Bicep
# ------------------------------------------------------------------------------
# Deploy all Azure resources including:
#   - Resource Group
#   - AKS cluster with Azure CNI and monitoring enabled
#   - Azure Monitor Workspace (managed Prometheus)
#   - Azure Managed Grafana
#   - Virtual Network and subnet
#   - Log Analytics workspace
#   - Data Collection Rules for Prometheus metrics
#
# The deployment name includes a timestamp to make each deployment unique
# and trackable in Azure deployment history

# Generate unique deployment name with timestamp
DEPLOYMENT_NAME_WITH_TIMESTAMP="$DEPLOYMENT_NAME-$(date +%Y%m%d-%H%M%S)"
print_status "Deployment name: $DEPLOYMENT_NAME_WITH_TIMESTAMP"

# Deploy infrastructure with Bicep
print_status "Deploying Azure infrastructure (this may take 10-15 minutes)..."
if [ -n "$CURRENT_USER_OBJECT_ID" ]; then
    # Pass current user ID to Bicep for Grafana role assignment
    az deployment sub create --name "$DEPLOYMENT_NAME_WITH_TIMESTAMP" --location eastus --template-file "$BICEP_FILE" --parameters "$PARAMS_FILE" currentUserObjectId="$CURRENT_USER_OBJECT_ID" --output table
else
    # Deploy without Grafana role assignment
    az deployment sub create --name "$DEPLOYMENT_NAME_WITH_TIMESTAMP" --location eastus --template-file "$BICEP_FILE" --parameters "$PARAMS_FILE" --output table
fi

# ------------------------------------------------------------------------------
# Retrieve Deployment Outputs
# ------------------------------------------------------------------------------
# Extract important information from the Bicep deployment outputs including
# resource names and endpoints that will be used in subsequent steps

# Get outputs from deployment
print_status "Retrieving deployment outputs..."
RG_NAME=$(az deployment sub show \
    --name "$DEPLOYMENT_NAME_WITH_TIMESTAMP" \
    --query 'properties.outputs.resourceGroupName.value' -o tsv)

AKS_NAME=$(az deployment sub show \
    --name "$DEPLOYMENT_NAME_WITH_TIMESTAMP" \
    --query 'properties.outputs.aksClusterName.value' -o tsv)

GRAFANA_ENDPOINT=$(az deployment sub show \
    --name "$DEPLOYMENT_NAME_WITH_TIMESTAMP" \
    --query 'properties.outputs.grafanaEndpoint.value' -o tsv)

GRAFANA_NAME=$(az deployment sub show \
    --name "$DEPLOYMENT_NAME_WITH_TIMESTAMP" \
    --query 'properties.outputs.grafanaName.value' -o tsv)

# Validate that critical outputs were retrieved successfully
if [ -z "$RG_NAME" ] || [ -z "$AKS_NAME" ]; then
    print_error "Failed to retrieve deployment outputs. Please check the deployment."
    exit 1
fi

# Display deployment summary
print_status "Resource Group: $RG_NAME"
print_status "AKS Cluster: $AKS_NAME"
print_status "Grafana: $GRAFANA_NAME"
print_status "Grafana Endpoint: $GRAFANA_ENDPOINT"

if [ -n "$CURRENT_USER_OBJECT_ID" ]; then
    print_status "Grafana Admin role assigned to: $CURRENT_USER_EMAIL"
fi

# ------------------------------------------------------------------------------
# Configure kubectl Access to AKS Cluster
# ------------------------------------------------------------------------------
# Download and merge AKS cluster credentials into the local kubeconfig file
# This allows kubectl commands to interact with the newly created cluster

# Get AKS credentials
print_status "Getting AKS credentials..."
az aks get-credentials \
    --resource-group "$RG_NAME" \
    --name "$AKS_NAME" \
    --overwrite-existing

# Verify cluster access
print_status "Verifying cluster access..."
kubectl cluster-info

# ------------------------------------------------------------------------------
# Install cert-manager
# ------------------------------------------------------------------------------
# cert-manager automates the management and issuance of TLS certificates
# from various sources including Let's Encrypt. It will automatically:
#   - Request TLS certificates from Let's Encrypt
#   - Handle certificate renewals
#   - Store certificates as Kubernetes secrets
#
# We use the Helm chart with CRD installation enabled

print_status "Installing cert-manager..."

# Create namespace for cert-manager
kubectl create namespace "$CERT_MANAGER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Add Jetstack Helm repository (maintains cert-manager charts)
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install or upgrade cert-manager with custom values
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace "$CERT_MANAGER_NAMESPACE" \
    --version "$CERT_MANAGER_VERSION" \
    --values cert-manager-values.yaml \
    --wait \
    --timeout 5m

# Wait for all cert-manager components to be ready before proceeding
print_status "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/cert-manager \
    deployment/cert-manager-webhook \
    deployment/cert-manager-cainjector \
    -n "$CERT_MANAGER_NAMESPACE"

# ------------------------------------------------------------------------------
# Create Let's Encrypt ClusterIssuers
# ------------------------------------------------------------------------------
# ClusterIssuers define how cert-manager should request certificates
# We create two issuers:
#   - letsencrypt-staging: For testing (higher rate limits, untrusted certs)
#   - letsencrypt-prod: For production (trusted certs, lower rate limits)

# Create ClusterIssuers
print_status "Creating cert-manager ClusterIssuers..."
kubectl apply -f manifests/cluster-issuer.yaml

# ------------------------------------------------------------------------------
# Install Traefik Ingress Controller
# ------------------------------------------------------------------------------
# Traefik acts as the entry point for external traffic to reach ArgoCD
# It provides:
#   - L7 load balancing with Azure Load Balancer integration
#   - TLS termination using certificates from cert-manager
#   - IngressRoute CRD for advanced routing capabilities
#   - HTTP to HTTPS redirection

print_status "Installing Traefik ingress controller..."

# Create namespace for Traefik
kubectl create namespace "$TRAEFIK_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Add Traefik Helm repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install or upgrade Traefik with custom values
helm upgrade --install traefik traefik/traefik \
    --namespace "$TRAEFIK_NAMESPACE" \
    --version "$TRAEFIK_VERSION" \
    --values traefik-values.yaml \
    --wait \
    --timeout 5m

# Wait for Traefik deployment to be ready
print_status "Waiting for Traefik to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/traefik \
    -n "$TRAEFIK_NAMESPACE"

# ------------------------------------------------------------------------------
# Retrieve Traefik LoadBalancer IP Address
# ------------------------------------------------------------------------------
# Azure provisions a public IP address for the Traefik LoadBalancer service
# This IP must be configured in DNS to point to your custom domain
# We wait briefly for the LoadBalancer to be provisioned before checking

# Get Traefik LoadBalancer IP
print_status "Retrieving Traefik LoadBalancer IP..."
sleep 30  # Wait for LoadBalancer to provision

# Try to get IP address (or hostname for some cloud providers)
TRAEFIK_IP=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
             kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
             echo "pending")

if [ "$TRAEFIK_IP" != "pending" ]; then
    print_status "Traefik LoadBalancer IP: $TRAEFIK_IP"
    print_warning "Please ensure your DNS record for $ARGOCD_DOMAIN points to: $TRAEFIK_IP"
else
    print_warning "Traefik LoadBalancer IP is still pending."
fi

# ------------------------------------------------------------------------------
# Install ArgoCD
# ------------------------------------------------------------------------------
# ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes
# This installation includes:
#   - High availability configuration with multiple replicas
#   - Redis HA for improved reliability
#   - Horizontal Pod Autoscaling (HPA) enabled
#   - Metrics exposure for Prometheus monitoring
#   - Pre-configured Git repository access

print_status "Installing ArgoCD..."

# Create ArgoCD namespace
print_status "Creating ArgoCD namespace..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Add ArgoCD Helm repository
print_status "Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD using Helm with custom values
print_status "Installing ArgoCD with HA configuration..."
helm upgrade --install argocd argo/argo-cd \
    --namespace "$ARGOCD_NAMESPACE" \
    --version "$ARGOCD_VERSION" \
    --values argocd-values.yaml \
    --wait \
    --timeout 10m

# Wait for ArgoCD server to be ready before proceeding
print_status "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    -n "$ARGOCD_NAMESPACE"

# ------------------------------------------------------------------------------
# Configure ArgoCD Ingress and Monitoring
# ------------------------------------------------------------------------------
# Apply additional Kubernetes manifests for:
#   - IngressRoute: Exposes ArgoCD via Traefik with TLS
#   - Certificate: Requests TLS cert from Let's Encrypt
#   - ServiceMonitors: Enable Prometheus metrics collection for Azure Monitor

# Apply ArgoCD IngressRoute (after Traefik is installed)
print_status "Creating ArgoCD IngressRoute..."
kubectl apply -f manifests/argocd-ingress.yaml

# Apply ArgoCD ServiceMonitors for Azure Managed Prometheus
print_status "Creating ArgoCD ServiceMonitors for Azure Managed Prometheus..."
kubectl apply -f manifests/argocd-servicemonitors.yaml

# ------------------------------------------------------------------------------
# Retrieve ArgoCD Admin Password
# ------------------------------------------------------------------------------
# ArgoCD automatically generates a secure admin password on first installation
# This is stored in a Kubernetes secret and must be retrieved to access the UI

# Get ArgoCD initial admin password
print_status "Retrieving ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "admin")

# ==============================================================================
# Deployment Summary and Access Information
# ==============================================================================
# Display all necessary information for accessing and using the deployed
# infrastructure including URLs, credentials, and useful commands
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Traefik LoadBalancer:${NC}"
if [ "$TRAEFIK_IP" != "pending" ]; then
    echo -e "  IP Address: ${YELLOW}$TRAEFIK_IP${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Configure your DNS record:"
    echo -e "  ${GREEN}$ARGOCD_DOMAIN${NC} --> ${YELLOW}$TRAEFIK_IP${NC}"
    echo ""
    echo -e "  Once DNS is configured, access ArgoCD at:"
    echo -e "  ${GREEN}https://$ARGOCD_DOMAIN${NC}"
else
    echo -e "  Status: ${YELLOW}Pending${NC}"
    echo ""
    echo "  Run this command to get the IP:"
    echo "  kubectl get svc traefik -n $TRAEFIK_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
fi
echo ""
echo -e "${GREEN}ArgoCD Access Information:${NC}"
echo -e "  Namespace: ${YELLOW}$ARGOCD_NAMESPACE${NC}"
echo -e "  Username:  ${YELLOW}admin${NC}"
echo -e "  Password:  ${YELLOW}$ARGOCD_PASSWORD${NC}"
echo -e "  URL:       ${GREEN}https://$ARGOCD_DOMAIN${NC}"
echo ""
echo -e "${GREEN}Azure Managed Grafana:${NC}"
echo -e "  Name:      ${YELLOW}$GRAFANA_NAME${NC}"
echo -e "  URL:       ${GREEN}$GRAFANA_ENDPOINT${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} Grafana is integrated with:"
echo "  - Azure Monitor Workspace (Managed Prometheus)"
echo "  - AKS cluster metrics and logs"
echo "  - Pre-configured dashboards for Kubernetes monitoring"
echo ""
echo -e "${YELLOW}Note:${NC} It may take a few minutes for the TLS certificate to be issued by Let's Encrypt."
echo ""
echo -e "${GREEN}Alternative Access (Port Forward):${NC}"
echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo "  Then access ArgoCD at: https://localhost:8080"
echo ""
echo -e "${GREEN}Useful Commands:${NC}"
echo "  # Check certificate status"
echo "  kubectl get certificate -n $ARGOCD_NAMESPACE"
echo "  kubectl describe certificate argocd-tls -n $ARGOCD_NAMESPACE"
echo ""
echo "  # Check Traefik IngressRoute"
echo "  kubectl get ingressroute -n $ARGOCD_NAMESPACE"
echo ""
echo "  # View Traefik dashboard (optional)"
echo "  kubectl port-forward -n $TRAEFIK_NAMESPACE svc/traefik 9000:9000"
echo "  Then access: http://localhost:9000/dashboard/"
echo ""
echo "  # Install ArgoCD CLI (optional)"
echo "  brew install argocd  # macOS"
echo ""
echo "  # Login with ArgoCD CLI (via domain)"
echo "  argocd login $ARGOCD_DOMAIN --username admin --password $ARGOCD_PASSWORD"
echo ""
echo "  # Or login via port-forward"
echo "  argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure"
echo ""
echo "  # Change admin password"
echo "  argocd account update-password"
echo ""
echo -e "${GREEN}========================================${NC}"
