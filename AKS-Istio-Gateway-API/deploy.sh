#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AKS Istio Gateway API Demo - Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    echo "Please install Terraform from https://www.terraform.io/downloads"
    exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if kubectl is installed
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
echo -e "${GREEN}✓ Logged into Azure subscription: ${SUBSCRIPTION}${NC}"
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

# Navigate to Terraform directory
cd terraform

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init
echo ""

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}Creating terraform.tfvars from example...${NC}"
    cp terraform.tfvars.example terraform.tfvars
    echo -e "${GREEN}✓ Created terraform.tfvars - please review and customize if needed${NC}"
    echo ""
fi

# Plan infrastructure
echo -e "${YELLOW}Planning infrastructure deployment...${NC}"
terraform plan -out=tfplan
echo ""

# Ask for confirmation
read -p "Do you want to proceed with deployment? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo -e "${RED}Deployment cancelled${NC}"
    exit 0
fi

# Apply infrastructure
echo -e "${YELLOW}Deploying infrastructure...${NC}"
echo "This may take 10-15 minutes..."
terraform apply tfplan
echo ""

# Get outputs
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw cluster_name)

echo -e "${GREEN}✓ Infrastructure deployed successfully${NC}"
echo ""

# Get AKS credentials
echo -e "${YELLOW}Getting AKS credentials...${NC}"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
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
cd ../kubernetes-manifests

echo "Deploying httpbin application..."
kubectl apply -f 01-httpbin-app.yaml

echo "Deploying Gateway and HTTPRoute for httpbin..."
kubectl apply -f 02-gateway-httproute.yaml

echo "Deploying echo applications (v1 and v2)..."
kubectl apply -f 03-echo-apps.yaml

echo "Deploying advanced routing examples..."
kubectl apply -f 04-advanced-traffic-splitting.yaml
kubectl apply -f 05-header-based-routing.yaml
kubectl apply -f 06-path-based-routing.yaml

echo ""
echo -e "${GREEN}✓ Sample applications deployed${NC}"
echo ""

# Wait for Gateway to be programmed
echo -e "${YELLOW}Waiting for Gateway to be programmed...${NC}"
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
