#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
MANIFESTS_DIR="$SCRIPT_DIR/kubernetes-manifests"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}AKS Istio Service Mesh Add-on Demo - Deploy${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

#############################################
# Prerequisites
#############################################
echo -e "${YELLOW}Checking prerequisites...${NC}"
for cmd in az terraform kubectl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: '$cmd' is not installed or not on PATH${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ az, terraform, kubectl, jq found${NC}"

if ! az account show &>/dev/null; then
    echo -e "${RED}Error: Not logged into Azure. Run 'az login' first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Logged into Azure subscription: $(az account show --query name -o tsv)${NC}"

# aks-preview is only needed for optional day-2 CLI diagnostics
# (az aks mesh get-revisions / get-upgrades) - install it best-effort.
if az extension show --name aks-preview &>/dev/null; then
    az extension update --name aks-preview --only-show-errors || true
else
    az extension add --name aks-preview --only-show-errors || true
fi
echo ""

#############################################
# Terraform: provision AKS + the Istio add-on
#############################################
echo -e "${YELLOW}Running terraform init/apply...${NC}"
pushd "$TF_DIR" >/dev/null
terraform init -input=false
terraform apply -auto-approve
popd >/dev/null
echo -e "${GREEN}✓ Terraform apply complete${NC}"
echo ""

RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw resource_group_name)
CLUSTER_NAME=$(terraform -chdir="$TF_DIR" output -raw aks_cluster_name)
ISTIO_REVISION=$(terraform -chdir="$TF_DIR" output -json istio_revisions | jq -r '.[0]')

echo -e "${BLUE}Resource group:${NC} $RESOURCE_GROUP"
echo -e "${BLUE}Cluster name:${NC}   $CLUSTER_NAME"
echo -e "${BLUE}Istio revision:${NC} $ISTIO_REVISION"
echo ""

#############################################
# Connect kubectl + verify the add-on
#############################################
echo -e "${YELLOW}Fetching AKS credentials...${NC}"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

echo -e "${YELLOW}Waiting for istiod ($ISTIO_REVISION) to be ready...${NC}"
kubectl wait --for=condition=Ready pod -l "app=istiod,istio.io/rev=$ISTIO_REVISION" -n aks-istio-system --timeout=300s
echo -e "${GREEN}✓ istiod is running${NC}"
echo ""

#############################################
# Enable sidecar injection + deploy bookinfo
#############################################
echo -e "${YELLOW}Labeling the 'default' namespace for sidecar injection...${NC}"
kubectl label namespace default "istio.io/rev=$ISTIO_REVISION" --overwrite
echo -e "${GREEN}✓ Namespace labeled${NC}"
echo ""

ISTIO_MINOR=$(echo "$ISTIO_REVISION" | sed -E 's/asm-([0-9]+)-([0-9]+)/\1.\2/')
BOOKINFO_URL="https://raw.githubusercontent.com/istio/istio/release-${ISTIO_MINOR}/samples/bookinfo/platform/kube/bookinfo.yaml"
echo -e "${YELLOW}Deploying the bookinfo sample app (Istio ${ISTIO_MINOR} manifests)...${NC}"
kubectl apply -f "$BOOKINFO_URL"
echo -e "${GREEN}✓ bookinfo applied${NC}"
echo ""

echo -e "${YELLOW}Waiting for bookinfo pods to become Ready (sidecar injection)...${NC}"
kubectl wait --for=condition=Ready pod -l app --timeout=300s -n default || true
echo ""

#############################################
# Traffic management + security baseline
#############################################
echo -e "${YELLOW}Applying baseline traffic management (DestinationRule + all-v1 VirtualService)...${NC}"
kubectl apply -f "$MANIFESTS_DIR/traffic-management/destination-rule-reviews.yaml"
kubectl apply -f "$MANIFESTS_DIR/traffic-management/virtualservice-all-v1.yaml"
echo -e "${GREEN}✓ Baseline routing applied (100% reviews-v1)${NC}"
echo ""

echo -e "${YELLOW}Enforcing mesh-wide strict mTLS (PeerAuthentication)...${NC}"
kubectl apply -f "$MANIFESTS_DIR/security/peer-authentication-strict.yaml"
echo -e "${GREEN}✓ Strict mTLS enabled${NC}"
echo ""

#############################################
# Ingress gateway
#############################################
echo -e "${YELLOW}Applying the Istio Gateway + VirtualService for productpage...${NC}"
kubectl apply -f "$MANIFESTS_DIR/ingress/gateway.yaml"
kubectl apply -f "$MANIFESTS_DIR/ingress/virtualservice-productpage.yaml"
echo -e "${GREEN}✓ Ingress routing applied${NC}"
echo ""

echo -e "${YELLOW}Waiting for the external ingress gateway's public IP...${NC}"
for _ in $(seq 1 30); do
    GATEWAY_IP=$(kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -n "$GATEWAY_IP" ]; then
        break
    fi
    sleep 10
done

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${BLUE}Istio revision:${NC}        $ISTIO_REVISION"
if [ -n "${GATEWAY_IP:-}" ]; then
    echo -e "${BLUE}Bookinfo app:${NC}          http://${GATEWAY_IP}/productpage"
else
    echo -e "${YELLOW}Gateway IP not ready yet - check later with:${NC}"
    echo "  kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress"
fi
GRAFANA_ENDPOINT=$(terraform -chdir="$TF_DIR" output -raw grafana_endpoint 2>/dev/null || true)
if [ -n "$GRAFANA_ENDPOINT" ] && [ "$GRAFANA_ENDPOINT" != "null" ]; then
    echo -e "${BLUE}Azure Managed Grafana:${NC} $GRAFANA_ENDPOINT"
fi
echo ""
echo "Next steps (see README.md 'Demo Walkthrough' for details):"
echo "  - Canary rollout:     kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-canary-v3.yaml"
echo "  - Header-based route: kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-user-routing.yaml"
echo "  - Fault injection:    kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-fault-injection.yaml"
echo "  - Zero-trust authz:   kubectl apply -f kubernetes-manifests/security/authorization-policy-ratings.yaml"
