#!/bin/bash
set -euo pipefail

# ============================================================
# Deploy AKS with Advanced Container Networking Services (ACNS)
# ============================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="aks-acns-demo"
LOCATION="eastus"
CLUSTER_NAME="aks-acns-cluster"
DEPLOYMENT_NAME="acns-deployment-$(date +%Y%m%d-%H%M%S)"

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

    # Verify Azure CLI version >= 2.79.0
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    print_message "Azure CLI version: $AZ_VERSION"

    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is not installed. Install it to run the demo steps."
    fi

    print_message "Prerequisites check passed!"
}

create_resource_group() {
    print_message "Creating resource group: $RESOURCE_GROUP in $LOCATION..."

    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output table

    print_message "Resource group created successfully!"
}

deploy_bicep() {
    print_message "Starting Bicep deployment: $DEPLOYMENT_NAME..."
    print_warning "This deployment may take 10-15 minutes..."

    # Get current user object ID for Grafana Admin role
    USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")

    if [ -z "$USER_OBJECT_ID" ]; then
        print_warning "Could not retrieve user object ID. Grafana Admin role will not be assigned."
    fi

    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --parameters userId="$USER_OBJECT_ID" \
        --output table

    print_message "Deployment completed successfully!"
}

get_outputs() {
    print_message "Retrieving deployment outputs..."

    CLUSTER_FQDN=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs.clusterFqdn.value \
        --output tsv)

    NETWORK_DATAPLANE=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs.networkDataplane.value \
        --output tsv)

    GRAFANA_URL=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs.grafanaEndpoint.value \
        --output tsv)

    PROMETHEUS_ID=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs.prometheusResourceId.value \
        --output tsv)

    print_message "Outputs retrieved successfully!"
}

configure_aks_access() {
    print_message "Configuring AKS cluster access..."

    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --overwrite-existing

    print_message "AKS credentials configured!"
}

verify_acns() {
    print_message "Verifying ACNS configuration..."

    az aks show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "networkProfile.advancedNetworking" \
        --output json

    echo ""
    print_message "Verifying Cilium pods..."
    kubectl get pods -n kube-system -l k8s-app=cilium

    echo ""
    print_message "Verifying Azure Monitor metrics pods..."
    kubectl get pods -n kube-system -o wide | grep ama- || print_warning "Azure Monitor pods not yet ready. They may take a few minutes to start."

    print_message "ACNS verification complete!"
}

display_summary() {
    echo ""
    echo "=========================================="
    echo "   Deployment Summary"
    echo "=========================================="
    echo ""
    echo "Resource Group:        $RESOURCE_GROUP"
    echo "AKS Cluster:           $CLUSTER_NAME"
    echo "Cluster FQDN:          $CLUSTER_FQDN"
    echo "Network Dataplane:     $NETWORK_DATAPLANE"
    echo "Grafana URL:           $GRAFANA_URL"
    echo "Prometheus ID:         $PROMETHEUS_ID"
    echo ""
    echo "=========================================="
    echo "   ACNS Features Enabled"
    echo "=========================================="
    echo ""
    echo "  ✅ Container Network Observability"
    echo "  ✅ Container Network Security (FQDN + L7)"
    echo "  ✅ Container Network Performance (eBPF)"
    echo "  ✅ Azure Managed Prometheus"
    echo "  ✅ Azure Managed Grafana"
    echo ""
    echo "=========================================="
    echo "   Grafana Dashboards"
    echo "=========================================="
    echo ""
    echo "Open Grafana at: $GRAFANA_URL"
    echo ""
    echo "Pre-built dashboards under Azure Managed Prometheus:"
    echo "  - Kubernetes / Networking / Clusters"
    echo "  - Kubernetes / Networking / DNS (Cluster)"
    echo "  - Kubernetes / Networking / DNS (Workload)"
    echo "  - Kubernetes / Networking / Drops (Workload)"
    echo "  - Kubernetes / Networking / Pod Flows (Namespace)"
    echo "  - Kubernetes / Networking / Pod Flows (Workload)"
    echo "  - Kubernetes / Networking / L7 (Namespace)"
    echo "  - Kubernetes / Networking / L7 (Workload)"
    echo ""
    echo "=========================================="
    echo "   Next Steps"
    echo "=========================================="
    echo ""
    echo "1. Run the FQDN filtering demo:"
    echo "   kubectl create ns demo"
    echo "   kubectl apply -f fqdn-filtering-policy.yaml -n demo"
    echo "   kubectl apply -f sample-deployment.yaml -n demo"
    echo ""
    echo "2. Run the L7 policy demo:"
    echo "   kubectl create ns l7-demo"
    echo "   kubectl apply -f l7-demo-apps.yaml -n l7-demo"
    echo "   kubectl apply -f l7-policy.yaml -n l7-demo"
    echo ""
    echo "3. View metrics in Grafana:"
    echo "   Open $GRAFANA_URL"
    echo "   Navigate to Dashboards > Azure Managed Prometheus"
    echo ""
    echo "4. See README.md for full demo walkthrough"
    echo ""
    echo "=========================================="
    echo ""
}

# Main execution
main() {
    print_message "Starting AKS ACNS deployment..."

    check_prerequisites
    create_resource_group
    deploy_bicep
    get_outputs
    configure_aks_access
    verify_acns
    display_summary

    print_message "Deployment completed successfully!"
}

main
