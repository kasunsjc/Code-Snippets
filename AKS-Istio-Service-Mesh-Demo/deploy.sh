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
OBSERVABILITY_DIR="$SCRIPT_DIR/kubernetes-manifests/observability"

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
EXTERNAL_GATEWAY_ENABLED=$(terraform -chdir="$TF_DIR" output -raw external_ingress_gateway_enabled)
MONITORING_ENABLED=$(terraform -chdir="$TF_DIR" output -raw monitoring_enabled)

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

if [ "$MONITORING_ENABLED" = "true" ]; then
    echo -e "${YELLOW}Waiting for the Azure Managed Prometheus PodMonitor CRD...${NC}"
    PODMONITOR_CRD="podmonitors.azmonitoring.coreos.com"
    for _ in $(seq 1 24); do
        if kubectl get crd "$PODMONITOR_CRD" >/dev/null 2>&1; then
            break
        fi
        sleep 5
    done
    if ! kubectl wait --for=condition=Established "crd/$PODMONITOR_CRD" --timeout=120s >/dev/null; then
        echo -e "${RED}Error: Azure Managed Prometheus PodMonitor CRD is unavailable. Confirm enable_monitoring=true and retry.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ PodMonitor CRD is ready${NC}"
    echo ""

    echo -e "${YELLOW}Configuring Istio proxy metric scraping...${NC}"
    kubectl apply -f "$OBSERVABILITY_DIR/istio-bookinfo-podmonitor.yaml"
    echo -e "${GREEN}✓ Istio PodMonitor applied${NC}"
    echo ""
fi

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

echo -e "${YELLOW}Waiting for the Bookinfo deployments to roll out...${NC}"
for deployment in details-v1 productpage-v1 ratings-v1 reviews-v1 reviews-v2 reviews-v3; do
    kubectl rollout status "deployment/${deployment}" -n default --timeout=300s
done

echo -e "${YELLOW}Verifying that Bookinfo pods are Ready with injected sidecars...${NC}"
# Istio revisions on Kubernetes 1.29+ (e.g. asm-1-30) inject istio-proxy as a
# "native sidecar" initContainer (restartPolicy: Always) instead of a regular
# container, so its status lives under initContainerStatuses, not
# containerStatuses - check both so this works on either sidecar model.
for selector in \
    "app=details,version=v1" \
    "app=productpage,version=v1" \
    "app=ratings,version=v1" \
    "app=reviews,version=v1" \
    "app=reviews,version=v2" \
    "app=reviews,version=v3"; do
    if ! kubectl get pods -n default -l "$selector" -o json | jq -e '
        (.items | length) > 0 and
        all(.items[];
            (.status.containerStatuses // []) + (.status.initContainerStatuses // []) as $allStatuses |
            .metadata.deletionTimestamp == null and
            .status.phase == "Running" and
            any($allStatuses[]; .name == "istio-proxy" and .ready == true) and
            any((.status.containerStatuses // [])[]; .name != "istio-proxy" and .ready == true)
        )
    ' >/dev/null; then
        echo -e "${RED}Error: Bookinfo pods for selector '$selector' are not fully ready with injected sidecars.${NC}"
        kubectl get pods -n default -l "$selector"
        exit 1
    fi
done
echo -e "${GREEN}✓ Bookinfo pods are ready with sidecars${NC}"
echo ""

GATEWAY_IP=""
if [ "$EXTERNAL_GATEWAY_ENABLED" = "true" ]; then
    echo -e "${YELLOW}Waiting for the external ingress gateway's public IP...${NC}"
    for _ in $(seq 1 30); do
        GATEWAY_IP=$(kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [ -n "$GATEWAY_IP" ]; then
            break
        fi
        sleep 10
    done

    if [ -n "$GATEWAY_IP" ]; then
        echo -e "${GREEN}✓ External gateway IP is ready${NC}"
    else
        echo -e "${YELLOW}Gateway IP is not ready yet. Check it later with:${NC}"
        echo "  kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress"
    fi
fi
echo ""

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${BLUE}Istio revision:${NC}        $ISTIO_REVISION"
if [ -n "${GATEWAY_IP:-}" ]; then
    echo -e "${BLUE}Gateway IP:${NC}            $GATEWAY_IP"
    echo -e "${BLUE}Bookinfo app:${NC}          Not exposed yet; apply the optional Gateway and VirtualService demos"
    echo "  kubectl apply -f kubernetes-manifests/ingress/gateway.yaml"
    echo "  kubectl apply -f kubernetes-manifests/ingress/virtualservice-productpage.yaml"
    echo "  curl http://$GATEWAY_IP/productpage"
elif [ "$EXTERNAL_GATEWAY_ENABLED" = "true" ]; then
    echo -e "${YELLOW}Gateway IP not ready yet - check later with:${NC}"
    echo "  kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress"
else
    echo -e "${BLUE}External gateway:${NC}       Disabled"
fi
GRAFANA_ENDPOINT=$(terraform -chdir="$TF_DIR" output -raw grafana_endpoint 2>/dev/null || true)
if [ -n "$GRAFANA_ENDPOINT" ] && [ "$GRAFANA_ENDPOINT" != "null" ]; then
    echo -e "${BLUE}Azure Managed Grafana:${NC} $GRAFANA_ENDPOINT"
fi
echo ""
echo "Next steps (see README.md 'Demo Walkthrough' for details):"
if [ "$MONITORING_ENABLED" = "true" ]; then
    echo "  - Grafana dashboard:   import grafana/istio-service-mesh-dashboard.json into Azure Managed Grafana"
fi
echo "  - Gateway listener:   kubectl apply -f kubernetes-manifests/ingress/gateway.yaml"
echo "  - HTTP routing:        kubectl apply -f kubernetes-manifests/ingress/virtualservice-productpage.yaml"
echo "  - Deterministic route: kubectl apply -f kubernetes-manifests/traffic-management/destination-rule-reviews.yaml && kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-all-v1.yaml"
echo "  - Canary rollout:     kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-canary-v3.yaml"
echo "  - Header-based route: kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-user-routing.yaml"
echo "  - Fault injection:    kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-fault-injection.yaml"
echo "  - Strict mTLS:        kubectl apply -f kubernetes-manifests/security/peer-authentication-strict.yaml"
echo "  - Zero-trust authz:   kubectl apply -f kubernetes-manifests/security/authorization-policy-ratings.yaml"
