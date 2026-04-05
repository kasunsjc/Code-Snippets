#!/bin/bash

# Deployment script for BYO CNI AKS with Cilium
# This script deploys the AKS cluster and installs Cilium CNI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
RESOURCE_GROUP_NAME="rg-byocni-cilium-demo"
LOCATION="eastus"
DEPLOYMENT_NAME="byocni-deployment-$(date +%Y%m%d-%H%M%S)"
CILIUM_VERSION="1.18.7"

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

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Check Helm
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install it first."
        print_info "Install via: brew install helm (macOS) or https://helm.sh/docs/intro/install/"
        exit 1
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first."
        exit 1
    fi

    # Check Cilium CLI (optional)
    if ! command -v cilium &> /dev/null; then
        print_warning "Cilium CLI is not installed. It's recommended for status checks."
        print_info "Install via: brew install cilium-cli (macOS)"
        print_info "Or: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli"
    fi

    print_message "Prerequisites check passed!"
}

create_resource_group() {
    print_message "Creating resource group: $RESOURCE_GROUP_NAME in $LOCATION..."

    az group create \
        --name "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --output table

    print_message "Resource group created successfully!"
}

deploy_bicep() {
    print_message "Starting Bicep deployment: $DEPLOYMENT_NAME..."
    print_warning "This deployment may take 10-15 minutes..."

    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file main.bicep \
        --parameters main.bicepparam \
        --output table

    print_message "Bicep deployment completed successfully!"
}

get_outputs() {
    print_message "Retrieving deployment outputs..."

    AKS_CLUSTER_NAME=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query properties.outputs.aksClusterName.value \
        --output tsv)

    print_message "AKS Cluster: $AKS_CLUSTER_NAME"
}

configure_aks_access() {
    print_message "Configuring AKS cluster access..."

    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing

    print_message "AKS credentials configured!"
}

wait_for_nodes() {
    print_message "Waiting for nodes to be ready..."

    # Nodes won't be fully Ready until CNI is installed, but wait for them to appear
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$NODE_COUNT" -ge 2 ]; then
            print_message "Found $NODE_COUNT nodes in the cluster."
            break
        fi
        attempt=$((attempt + 1))
        print_info "Waiting for nodes to appear... (attempt $attempt/$max_attempts)"
        sleep 10
    done

    if [ "$NODE_COUNT" -lt 2 ]; then
        print_error "Timed out waiting for nodes. Check cluster status."
        exit 1
    fi

    print_info "Note: Nodes will show 'NotReady' until Cilium CNI is installed."
    kubectl get nodes -o wide
}

install_cilium() {
    print_message "Installing Cilium CNI v${CILIUM_VERSION}..."

    # Add Cilium Helm repo
    helm repo add cilium https://helm.cilium.io/
    helm repo update

    # Install Cilium with AKS-compatible settings
    helm install cilium cilium/cilium \
        --version "${CILIUM_VERSION}" \
        --namespace kube-system \
        --set aksbyocni.enabled=true \
        --set nodeinit.enabled=true \
        --set hubble.relay.enabled=true \
        --set hubble.ui.enabled=true \
        --set hubble.metrics.enableOpenMetrics=true \
        --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
        --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.244.0.0/16}"

    print_message "Cilium Helm chart installed!"
}

wait_for_cilium() {
    print_message "Waiting for Cilium to be ready..."

    # Wait for Cilium pods
    kubectl -n kube-system rollout status daemonset/cilium --timeout=300s
    kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s

    # Wait for Hubble relay
    kubectl -n kube-system rollout status deployment/hubble-relay --timeout=300s

    print_message "Cilium is ready!"

    # Show Cilium status
    echo ""
    kubectl -n kube-system get pods -l app.kubernetes.io/part-of=cilium -o wide
    echo ""

    # If Cilium CLI is available, show detailed status
    if command -v cilium &> /dev/null; then
        echo ""
        print_message "Cilium CLI Status:"
        cilium status --wait
    fi
}

verify_nodes() {
    print_message "Verifying all nodes are Ready..."

    local max_attempts=20
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        NOT_READY=$(kubectl get nodes --no-headers | grep -c "NotReady" || true)
        if [ "$NOT_READY" -eq 0 ]; then
            print_message "All nodes are Ready!"
            kubectl get nodes -o wide
            return 0
        fi
        attempt=$((attempt + 1))
        print_info "Waiting for all nodes to become Ready... (attempt $attempt/$max_attempts)"
        sleep 15
    done

    print_warning "Some nodes may still be NotReady. Check manually."
    kubectl get nodes -o wide
}

display_summary() {
    echo ""
    echo "=========================================="
    echo "   BYO CNI AKS + Cilium - Deployment Summary"
    echo "=========================================="
    echo ""
    echo "Resource Group:    $RESOURCE_GROUP_NAME"
    echo "AKS Cluster:       $AKS_CLUSTER_NAME"
    echo "Cilium Version:    $CILIUM_VERSION"
    echo "Hubble UI:         Enabled"
    echo "Hubble Relay:      Enabled"
    echo ""
    echo "=========================================="
    echo "   Cilium Components"
    echo "=========================================="
    echo ""
    kubectl -n kube-system get pods -l app.kubernetes.io/part-of=cilium --no-headers
    echo ""
    echo "=========================================="
    echo "   Next Steps"
    echo "=========================================="
    echo ""
    echo "1. Access Hubble UI:"
    echo "   kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
    echo "   Then open: http://localhost:12000"
    echo ""
    echo "2. Run Cilium connectivity test:"
    echo "   cilium connectivity test"
    echo ""
    echo "3. Deploy sample apps with network policies:"
    echo "   kubectl apply -f sample-apps/"
    echo ""
    echo "4. Check Cilium status:"
    echo "   cilium status"
    echo ""
    echo "5. View Hubble flows:"
    echo "   hubble observe --follow"
    echo ""
    echo "=========================================="
}

# Main execution
echo ""
echo "=========================================="
echo "   BYO CNI AKS + Cilium - Deployment"
echo "=========================================="
echo ""

check_prerequisites
create_resource_group
deploy_bicep
get_outputs
configure_aks_access
wait_for_nodes
install_cilium
wait_for_cilium
verify_nodes
display_summary
