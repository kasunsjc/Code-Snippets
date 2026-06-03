#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AKS Istio Gateway API Demo - Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Configuration Variables
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-istio-gateway-demo}"
LOCATION="${LOCATION:-eastus}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-istio-gateway-demo}"
VNET_NAME="${VNET_NAME:-vnet-aks-istio-demo}"
SUBNET_NAME="${SUBNET_NAME:-snet-aks}"
NODE_COUNT="${NODE_COUNT:-2}"
NODE_SIZE="${NODE_SIZE:-Standard_D4s_v5}"
K8S_VERSION="${K8S_VERSION:-1.31}"

echo -e "${BLUE}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Node Count: $NODE_COUNT"
echo "  Node Size: $NODE_SIZE"
echo "  Kubernetes Version: $K8S_VERSION"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Please install kubectl from https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Check Azure login
echo -e "${YELLOW}Checking Azure login status...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged into Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✓ Logged into Azure subscription: ${SUBSCRIPTION}${NC}"
echo ""

# Install/update AKS preview extension
echo -e "${YELLOW}Ensuring aks-preview CLI extension is installed...${NC}"
if az extension show --name aks-preview &> /dev/null; then
    echo "Updating aks-preview extension..."
    az extension update --name aks-preview
else
    echo "Installing aks-preview extension..."
    az extension add --name aks-preview
fi
echo -e "${GREEN}✓ aks-preview extension ready${NC}"
echo ""

# Register preview features
echo -e "${YELLOW}Registering required preview features...${NC}"
echo "Note: This may take several minutes if features are not already registered"

az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview" || true
az feature register --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview" || true

# Wait for features to be registered
echo -e "${YELLOW}Waiting for features to be registered...${NC}"
for feature in "ManagedGatewayAPIPreview" "AppRoutingIstioGatewayAPIPreview"; do
    echo -n "Checking $feature... "
    while true; do
        state=$(az feature show --namespace "Microsoft.ContainerService" --name "$feature" --query properties.state -o tsv 2>/dev/null || echo "NotFound")
        if [[ "$state" == "Registered" ]]; then
            echo -e "${GREEN}Registered${NC}"
            break
        elif [[ "$state" == "NotFound" ]]; then
            echo -e "${RED}Failed to register${NC}"
            exit 1
        else
            echo -n "."
            sleep 10
        fi
    done
done

# Re-register the provider
echo -e "${YELLOW}Re-registering Microsoft.ContainerService provider...${NC}"
az provider register --namespace Microsoft.ContainerService
echo ""

# Create Resource Group
echo -e "${YELLOW}Creating resource group...${NC}"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags "Environment=Demo" "Project=AKS-Istio-Gateway-API" "ManagedBy=AzureCLI"

echo -e "${GREEN}✓ Resource group created${NC}"
echo ""

# Create Virtual Network
echo -e "${YELLOW}Creating virtual network...${NC}"
az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --address-prefix 10.0.0.0/16 \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefix 10.0.0.0/22

SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$SUBNET_NAME" \
    --query id -o tsv)

echo -e "${GREEN}✓ Virtual network created${NC}"
echo ""

# Create AKS Cluster with Gateway API and App Routing (Istio)
echo -e "${YELLOW}Creating AKS cluster with Gateway API and Istio app routing...${NC}"
echo "This may take 10-15 minutes..."
echo ""

az aks create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --location "$LOCATION" \
    --kubernetes-version "$K8S_VERSION" \
    --node-count "$NODE_COUNT" \
    --node-vm-size "$NODE_SIZE" \
    --network-plugin azure \
    --vnet-subnet-id "$SUBNET_ID" \
    --service-cidr 10.1.0.0/16 \
    --dns-service-ip 10.1.0.10 \
    --enable-managed-identity \
    --enable-gateway-api \
    --enable-app-routing-istio \
    --tier standard \
    --node-osdisk-type Managed \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 3 \
    --tags "Environment=Demo" "Project=AKS-Istio-Gateway-API"

echo ""
echo -e "${GREEN}✓ AKS cluster created successfully${NC}"
echo ""

# Get AKS credentials
echo -e "${YELLOW}Getting AKS credentials...${NC}"
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

echo -e "${GREEN}✓ Credentials configured${NC}"
echo ""

# Wait for istiod to be ready
echo -e "${YELLOW}Waiting for Istio control plane to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=istiod -n aks-istio-system --timeout=300s
echo -e "${GREEN}✓ Istio control plane is ready${NC}"
echo ""

# Verify GatewayClass exists
echo -e "${YELLOW}Verifying Gateway API resources...${NC}"
kubectl get gatewayclass approuting-istio
echo ""

# Deploy sample applications
echo -e "${YELLOW}Deploying sample applications...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/kubernetes-manifests"

echo "Deploying httpbin application..."
kubectl apply -f "$MANIFESTS_DIR/01-httpbin-app.yaml"

echo "Deploying Gateway and HTTPRoute for httpbin..."
kubectl apply -f "$MANIFESTS_DIR/02-gateway-httproute.yaml"

echo "Deploying echo applications (v1 and v2)..."
kubectl apply -f "$MANIFESTS_DIR/03-echo-apps.yaml"

echo "Deploying advanced routing examples..."
kubectl apply -f "$MANIFESTS_DIR/04-advanced-traffic-splitting.yaml"
kubectl apply -f "$MANIFESTS_DIR/05-header-based-routing.yaml"
kubectl apply -f "$MANIFESTS_DIR/06-path-based-routing.yaml"

echo ""
echo -e "${GREEN}✓ Sample applications deployed${NC}"
echo ""

# Wait for Gateway to be programmed
echo -e "${YELLOW}Waiting for Gateways to be programmed...${NC}"
kubectl wait --for=condition=programmed gateway/httpbin-gateway --timeout=300s
kubectl wait --for=condition=programmed gateway/echo-gateway --timeout=300s
echo ""

# Get Gateway IP addresses
echo -e "${YELLOW}Retrieving Gateway IP addresses...${NC}"
HTTPBIN_IP=$(kubectl get gateway httpbin-gateway -o jsonpath='{.status.addresses[0].value}')
ECHO_IP=$(kubectl get gateway echo-gateway -o jsonpath='{.status.addresses[0].value}')

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Cluster Information:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Subscription: $SUBSCRIPTION"
echo ""
echo -e "${YELLOW}Gateway Information:${NC}"
echo "  httpbin-gateway IP: $HTTPBIN_IP"
echo "  echo-gateway IP: $ECHO_IP"
echo ""
echo -e "${YELLOW}Test Commands:${NC}"
echo ""
echo "1. Test httpbin service:"
echo "   curl -s -H 'Host: httpbin.example.com' http://$HTTPBIN_IP/get | jq"
echo ""
echo "2. Test echo service (canary deployment - 90% v1, 10% v2):"
echo "   for i in {1..10}; do curl -s -H 'Host: echo.example.com' http://$ECHO_IP/ | grep -o 'Echo v[12]'; done"
echo ""
echo "3. Test header-based routing:"
echo "   # Routes to v1 (default)"
echo "   curl -s -H 'Host: echo-headers.example.com' http://$ECHO_IP/ | grep -o 'Echo v[12]'"
echo "   # Routes to v2 (with header)"
echo "   curl -s -H 'Host: echo-headers.example.com' -H 'version: v2' http://$ECHO_IP/ | grep -o 'Echo v[12]'"
echo ""
echo "4. Test path-based routing:"
echo "   curl -s -H 'Host: app.example.com' http://$ECHO_IP/v1/ | grep -o 'Echo v[12]'"
echo "   curl -s -H 'Host: app.example.com' http://$ECHO_IP/v2/ | grep -o 'Echo v[12]'"
echo ""
echo -e "${YELLOW}Explore the cluster:${NC}"
echo "  kubectl get pods -n aks-istio-system"
echo "  kubectl get gateway"
echo "  kubectl get httproute"
echo "  kubectl describe gateway httpbin-gateway"
echo ""
echo -e "${YELLOW}Azure Portal:${NC}"
echo "  https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/overview"
echo ""
