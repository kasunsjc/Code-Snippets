#!/bin/bash

# Deployment script for AKS with Application Gateway for Containers
# Supports two deployment strategies:
#   - managed : ALB Controller manages AGFC lifecycle via ApplicationLoadBalancer CRD
#   - byo     : Bring Your Own — AGFC resource pre-created in Azure via Bicep
#
# Usage:
#   ./deploy.sh              # Deploys with 'managed' strategy (default)
#   ./deploy.sh managed      # Deploys with 'managed' strategy
#   ./deploy.sh byo          # Deploys with 'byo' strategy

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
DEPLOYMENT_STRATEGY="${1:-managed}"
RESOURCE_GROUP_NAME="rg-agfc-demo"
LOCATION="northeurope"
DEPLOYMENT_NAME="agfc-deployment-$(date +%Y%m%d-%H%M%S)"
AKS_NAME="agfc-aks-dev"
ALB_SUBNET_NAME="subnet-alb"
VNET_NAME="agfc-vnet-dev"
AGFC_NAME="agfc-agfc-dev"

# Validate strategy
if [[ "$DEPLOYMENT_STRATEGY" != "managed" && "$DEPLOYMENT_STRATEGY" != "byo" ]]; then
    echo -e "${RED}ERROR:${NC} Invalid deployment strategy: $DEPLOYMENT_STRATEGY"
    echo "Usage: $0 [managed|byo]"
    exit 1
fi

# Functions
print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

check_prerequisites() {
    print_message "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first."
        exit 1
    fi

    if [[ "$DEPLOYMENT_STRATEGY" == "byo" ]] && ! command -v envsubst &> /dev/null; then
        print_error "envsubst is required for the 'byo' deployment strategy. Please install it first."
        exit 1
    fi

    print_message "All prerequisites met."
}

register_providers() {
    print_message "Registering required resource providers..."

    az provider register --namespace Microsoft.ContainerService --wait
    az provider register --namespace Microsoft.Network --wait
    az provider register --namespace Microsoft.NetworkFunction --wait
    az provider register --namespace Microsoft.ServiceNetworking --wait

    print_message "Registering preview features..."
    az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview" 2>/dev/null || true
    az feature register --namespace "Microsoft.ContainerService" --name "ApplicationLoadBalancerPreview" 2>/dev/null || true

    print_info "Waiting for feature registration (this may take a few minutes)..."
    local features=("ManagedGatewayAPIPreview" "ApplicationLoadBalancerPreview")
    local timeout=1800
    local interval=30
    for feature in "${features[@]}"; do
        local elapsed=0
        while true; do
            local state
            state=$(az feature show --namespace "Microsoft.ContainerService" --name "$feature" --query "properties.state" -o tsv 2>/dev/null || echo "Unknown")
            print_info "Feature '$feature' state: $state"
            if [[ "$state" == "Registered" ]]; then
                break
            fi
            if [[ $elapsed -ge $timeout ]]; then
                print_warning "Timed out waiting for feature '$feature' to register. Current state: $state. Continuing anyway..."
                break
            fi
            sleep $interval
            elapsed=$((elapsed + interval))
        done
    done

    az extension add --name alb --upgrade 2>/dev/null || true
    az extension add --name aks-preview --upgrade 2>/dev/null || true

    print_message "Provider registration complete."
}

deploy_infrastructure() {
    print_message "Creating resource group: ${RESOURCE_GROUP_NAME}..."
    az group create --name "${RESOURCE_GROUP_NAME}" --location "${LOCATION}" --output none

    print_message "Deploying Bicep infrastructure (strategy: ${DEPLOYMENT_STRATEGY})..."
    az deployment group create \
        --name "${DEPLOYMENT_NAME}" \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --parameters deploymentStrategy="${DEPLOYMENT_STRATEGY}" \
        --output none

    print_message "Infrastructure deployment complete."
}

enable_alb_addon() {
    print_message "Enabling Gateway API and Application Load Balancer add-on on AKS..."

    az aks update \
        --name "${AKS_NAME}" \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --enable-oidc-issuer \
        --enable-workload-identity \
        --enable-gateway-api \
        --enable-application-load-balancer \
        --no-wait \
        --output none

    print_info "Waiting for AKS update to complete..."
    az aks wait --name "${AKS_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --updated

    print_message "ALB Controller add-on enabled."
}

get_credentials() {
    print_message "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --name "${AKS_NAME}" \
        --overwrite-existing
}

verify_alb_controller() {
    print_message "Verifying ALB Controller installation..."

    print_info "Waiting for ALB Controller pods to be ready..."
    sleep 15

    echo ""
    print_info "ALB Controller pods:"
    kubectl get pods -n kube-system | grep alb-controller || true

    echo ""
    print_info "Gateway classes:"
    kubectl get gatewayclass || true

    echo ""
    print_message "ALB Controller verification complete."
}

setup_permissions_managed() {
    print_message "Setting up permissions for ALB managed deployment..."

    MC_RESOURCE_GROUP=$(az aks show --name "${AKS_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --query "nodeResourceGroup" -o tsv)

    ALB_SUBNET_ID=$(az network vnet subnet show \
        --name "${ALB_SUBNET_NAME}" \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --vnet-name "${VNET_NAME}" \
        --query 'id' -o tsv)

    # Get the managed identity created by the add-on
    IDENTITY_NAME="applicationloadbalancer-${AKS_NAME}"
    PRINCIPAL_ID=$(az identity show -g "${MC_RESOURCE_GROUP}" -n "${IDENTITY_NAME}" --query principalId -o tsv 2>/dev/null)

    if [ -z "$PRINCIPAL_ID" ]; then
        print_warning "ALB managed identity not found yet. Waiting 60 seconds..."
        sleep 60
        PRINCIPAL_ID=$(az identity show -g "${MC_RESOURCE_GROUP}" -n "${IDENTITY_NAME}" --query principalId -o tsv)
    fi

    MC_RG_ID=$(az group show --name "${MC_RESOURCE_GROUP}" --query id -o tsv)

    print_info "Assigning AppGW for Containers Configuration Manager role to MC resource group..."
    az role assignment create \
        --assignee-object-id "${PRINCIPAL_ID}" \
        --assignee-principal-type ServicePrincipal \
        --scope "${MC_RG_ID}" \
        --role "fbc52c3f-28ad-4303-a892-8a056630b8f1" \
        --output none 2>/dev/null || true

    print_info "Assigning Network Contributor role on ALB subnet..."
    az role assignment create \
        --assignee-object-id "${PRINCIPAL_ID}" \
        --assignee-principal-type ServicePrincipal \
        --scope "${ALB_SUBNET_ID}" \
        --role "4d97b98b-1d4f-4787-a291-c67834d212e7" \
        --output none 2>/dev/null || true

    print_message "Permissions configured for ALB managed deployment."
}

setup_permissions_byo() {
    print_message "Setting up permissions for BYO deployment..."

    ALB_SUBNET_ID=$(az network vnet subnet show \
        --name "${ALB_SUBNET_NAME}" \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --vnet-name "${VNET_NAME}" \
        --query 'id' -o tsv)

    MC_RESOURCE_GROUP=$(az aks show --name "${AKS_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --query "nodeResourceGroup" -o tsv)

    # Get the managed identity created by the add-on
    IDENTITY_NAME="applicationloadbalancer-${AKS_NAME}"
    PRINCIPAL_ID=$(az identity show -g "${MC_RESOURCE_GROUP}" -n "${IDENTITY_NAME}" --query principalId -o tsv 2>/dev/null)

    if [ -z "$PRINCIPAL_ID" ]; then
        print_warning "ALB managed identity not found yet. Waiting 60 seconds..."
        sleep 60
        PRINCIPAL_ID=$(az identity show -g "${MC_RESOURCE_GROUP}" -n "${IDENTITY_NAME}" --query principalId -o tsv)
    fi

    RG_ID=$(az group show --name "${RESOURCE_GROUP_NAME}" --query id -o tsv)

    print_info "Assigning AppGW for Containers Configuration Manager role to resource group..."
    az role assignment create \
        --assignee-object-id "${PRINCIPAL_ID}" \
        --assignee-principal-type ServicePrincipal \
        --scope "${RG_ID}" \
        --role "fbc52c3f-28ad-4303-a892-8a056630b8f1" \
        --output none 2>/dev/null || true

    print_info "Assigning Network Contributor role on ALB subnet..."
    az role assignment create \
        --assignee-object-id "${PRINCIPAL_ID}" \
        --assignee-principal-type ServicePrincipal \
        --scope "${ALB_SUBNET_ID}" \
        --role "4d97b98b-1d4f-4787-a291-c67834d212e7" \
        --output none 2>/dev/null || true

    print_message "Permissions configured for BYO deployment."
}

deploy_alb_managed() {
    print_message "Deploying ApplicationLoadBalancer custom resource (ALB managed strategy)..."

    ALB_SUBNET_ID=$(az network vnet subnet show \
        --name "${ALB_SUBNET_NAME}" \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --vnet-name "${VNET_NAME}" \
        --query 'id' -o tsv)

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: alb-test-infra
EOF

    kubectl apply -f - <<EOF
apiVersion: alb.networking.azure.io/v1
kind: ApplicationLoadBalancer
metadata:
  name: alb-test
  namespace: alb-test-infra
spec:
  associations:
  - ${ALB_SUBNET_ID}
EOF

    print_info "Waiting for ApplicationLoadBalancer to be provisioned (this takes 5-6 minutes)..."
    sleep 30
    kubectl get applicationloadbalancer alb-test -n alb-test-infra -o yaml

    print_message "ApplicationLoadBalancer resource deployed."
}

deploy_sample_apps() {
    print_message "Deploying sample backend applications..."
    kubectl apply -f kubernetes-manifests/01-sample-apps.yaml
    print_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=backend-v1 -n test-infra --timeout=120s 2>/dev/null || true
    kubectl wait --for=condition=ready pod -l app=backend-v2 -n test-infra --timeout=120s 2>/dev/null || true
    print_message "Sample applications deployed."
}

deploy_gateway_managed() {
    print_message "Deploying Gateway and HTTPRoutes (ALB managed strategy)..."
    kubectl apply -f kubernetes-manifests/gateway-managed/02-gateway.yaml
    kubectl apply -f kubernetes-manifests/gateway-managed/03-httproute.yaml
    print_message "Gateway API resources deployed (ALB managed)."
    print_info "Additional examples (traffic splitting, SSL offloading, backend mTLS) can be deployed separately."
    print_info "See README.md for instructions."
}

deploy_gateway_byo() {
    print_message "Deploying Gateway and HTTPRoutes (BYO strategy)..."

    AGFC_ID=$(az network alb show --resource-group "${RESOURCE_GROUP_NAME}" --name "${AGFC_NAME}" --query id -o tsv)
    FRONTEND_NAME="frontend"

    # Apply the gateway template with BYO annotations
    export AGFC_ID FRONTEND_NAME
    envsubst < kubernetes-manifests/gateway-byo/02-gateway.yaml | kubectl apply -f -
    kubectl apply -f kubernetes-manifests/gateway-byo/03-httproute.yaml

    print_message "Gateway API resources deployed (BYO)."
}

wait_for_gateway() {
    print_message "Waiting for Gateway to get an address (this may take a few minutes)..."
    for i in $(seq 1 30); do
        FQDN=$(kubectl get gateway gateway-01 -n test-infra -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
        if [ -n "$FQDN" ]; then
            print_message "Gateway address assigned: ${FQDN}"
            return
        fi
        sleep 10
    done
    print_warning "Gateway address not yet available. Check status with: kubectl get gateway gateway-01 -n test-infra -o yaml"
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "   Deployment Summary"
    echo "=========================================="
    echo ""
    print_info "Resource Group:       ${RESOURCE_GROUP_NAME}"
    print_info "AKS Cluster:          ${AKS_NAME}"
    print_info "Deployment Strategy:  ${DEPLOYMENT_STRATEGY}"
    echo ""

    FQDN=$(kubectl get gateway gateway-01 -n test-infra -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "pending")
    print_info "Gateway FQDN: ${FQDN}"
    echo ""

    if [ "$FQDN" != "pending" ] && [ -n "$FQDN" ]; then
        print_message "Test the application:"
        echo ""
        echo "  # Default route -> backend-v1"
        echo "  curl http://${FQDN}/"
        echo ""
        echo "  # Path-based routing: /bar -> backend-v2"
        echo "  curl http://${FQDN}/bar"
        echo ""
        echo "  # Header + query + path routing -> backend-v2"
        echo "  curl http://${FQDN}/some/thing?great=example -H \"magic: foo\""
        echo ""
    else
        print_warning "Gateway address not yet assigned. Run this to check:"
        echo "  kubectl get gateway gateway-01 -n test-infra -o yaml"
    fi
    echo ""
}

# ===========================
# Main Execution
# ===========================
echo ""
echo "========================================================="
echo "   AKS + Application Gateway for Containers Deployment"
echo "   Strategy: ${DEPLOYMENT_STRATEGY}"
echo "========================================================="
echo ""

check_prerequisites
register_providers
deploy_infrastructure
enable_alb_addon
get_credentials
verify_alb_controller

if [ "$DEPLOYMENT_STRATEGY" == "managed" ]; then
    setup_permissions_managed
    deploy_alb_managed
    deploy_sample_apps
    deploy_gateway_managed
elif [ "$DEPLOYMENT_STRATEGY" == "byo" ]; then
    setup_permissions_byo
    deploy_sample_apps
    deploy_gateway_byo
fi

wait_for_gateway
print_summary

print_message "Deployment complete!"
