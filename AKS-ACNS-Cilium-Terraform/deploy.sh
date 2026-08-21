#!/bin/bash
set -euo pipefail

# ============================================================
# Deploy AKS with Advanced Container Networking Services (ACNS)
# using Terraform (Azure CNI overlay + Cilium data plane)
#
# Usage:
#   ./deploy.sh              # provision infra + verify ACNS
#   ./deploy.sh --enable-l7  # additionally enable L7 network policies
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
ENABLE_L7=false

for arg in "$@"; do
    case "$arg" in
        --enable-l7) ENABLE_L7=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() { echo -e "${GREEN}==>${NC} $1"; }
print_error()   { echo -e "${RED}ERROR:${NC} $1"; }
print_warning() { echo -e "${YELLOW}WARNING:${NC} $1"; }

check_prerequisites() {
    print_message "Checking prerequisites..."

    for tool in terraform az kubectl; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done

    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    print_message "Prerequisites check passed!"
}

terraform_apply() {
    print_message "Provisioning infrastructure with Terraform..."
    print_warning "This may take 10-15 minutes..."

    USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
    if [ -z "$USER_OBJECT_ID" ]; then
        print_warning "Could not retrieve user object ID. Grafana Admin role will not be assigned."
    fi

    terraform -chdir="$TF_DIR" init
    terraform -chdir="$TF_DIR" apply -auto-approve -var "user_object_id=$USER_OBJECT_ID"
}

get_credentials() {
    RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw resource_group_name)
    CLUSTER_NAME=$(terraform -chdir="$TF_DIR" output -raw cluster_name)

    print_message "Fetching AKS credentials..."
    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --overwrite-existing
}

configure_prometheus_hubble_metrics() {
    print_message "Enabling Hubble flow metrics for Managed Prometheus dashboards..."
    kubectl apply -f "$SCRIPT_DIR/kubernetes-manifests/06-prometheus-hubble-metrics.yaml" >/dev/null
    kubectl -n kube-system rollout status deployment/ama-metrics --timeout=5m
}

enable_l7_policies() {
    print_message "Enabling L7 advanced network policies (includes FQDN)..."
    print_warning "This 'az aks update' may take 5-10 minutes..."

    az aks update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --enable-acns \
        --acns-advanced-networkpolicies L7 \
        --output none

    print_message "L7 network policies enabled!"
}

verify_acns() {
    print_message "Verifying ACNS components..."

    echo ""
    echo "Cilium agents:"
    kubectl get pods -n kube-system -l k8s-app=cilium -o wide

    echo ""
    echo "Hubble relay:"
    kubectl get pods -n kube-system -l k8s-app=hubble-relay 2>/dev/null || \
        print_warning "hubble-relay pods not found yet; they can take a few minutes to appear."

    echo ""
    echo "Network data plane:"
    az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "{dataplane:networkProfile.networkDataplane, acns:networkProfile.advancedNetworking}" \
        --output json
}

show_summary() {
    GRAFANA_URL=$(terraform -chdir="$TF_DIR" output -raw grafana_endpoint)

    echo ""
    print_message "Deployment complete!"
    echo ""
    echo "  Resource group : $RESOURCE_GROUP"
    echo "  AKS cluster    : $CLUSTER_NAME"
    echo "  Grafana        : $GRAFANA_URL"
    echo ""
    echo "Next steps:"
    echo "  kubectl apply -f kubernetes-manifests/01-traffic-demo.yaml   # generate traffic"
    echo "  Open Grafana -> Dashboards -> Azure Managed Prometheus folder (Kubernetes / Networking)"
    echo "  See README.md for the Hubble, FQDN filtering, and L7 policy demos."
}

check_prerequisites
terraform_apply
get_credentials
configure_prometheus_hubble_metrics
if [ "$ENABLE_L7" = true ]; then
    enable_l7_policies
fi
verify_acns
show_summary
