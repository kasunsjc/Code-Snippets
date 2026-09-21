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
RENDERED_DIR="$SCRIPT_DIR/.rendered"
CERT_MANAGER_CHART_VERSION="1.16.2"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}AKS Istio Service Mesh Add-on Demo - Deploy${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

#############################################
# Prerequisites
#############################################
echo -e "${YELLOW}Checking prerequisites...${NC}"
for cmd in az terraform kubectl jq helm envsubst; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: '$cmd' is not installed or not on PATH${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ az, terraform, kubectl, jq, helm, envsubst found${NC}"
mkdir -p "$RENDERED_DIR"

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
SUBSCRIPTION_ID=$(terraform -chdir="$TF_DIR" output -raw subscription_id)
DNS_ZONE_NAME=$(terraform -chdir="$TF_DIR" output -raw dns_zone_name)
DNS_ZONE_RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw dns_zone_resource_group)
BOOKINFO_FQDN=$(terraform -chdir="$TF_DIR" output -raw bookinfo_fqdn)
BOOKINFO_SUBDOMAIN=$(terraform -chdir="$TF_DIR" output -raw bookinfo_subdomain)
CERT_MANAGER_CLIENT_ID=$(terraform -chdir="$TF_DIR" output -raw cert_manager_client_id)
ACME_EMAIL=$(terraform -chdir="$TF_DIR" output -raw acme_email)
export SUBSCRIPTION_ID DNS_ZONE_NAME DNS_ZONE_RESOURCE_GROUP BOOKINFO_FQDN CERT_MANAGER_CLIENT_ID ACME_EMAIL

echo -e "${BLUE}Resource group:${NC} $RESOURCE_GROUP"
echo -e "${BLUE}Cluster name:${NC}   $CLUSTER_NAME"
echo -e "${BLUE}Istio revision:${NC} $ISTIO_REVISION"
echo -e "${BLUE}Bookinfo FQDN:${NC}  $BOOKINFO_FQDN"
echo ""

#############################################
# Connect kubectl + verify the add-on
#############################################
echo -e "${YELLOW}Fetching AKS credentials...${NC}"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

#############################################
# cert-manager (Workload Identity, no client secret) + Azure DNS DNS-01
#############################################
echo -e "${YELLOW}Installing cert-manager...${NC}"
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
    --version "$CERT_MANAGER_CHART_VERSION" \
    --namespace cert-manager --create-namespace \
    --set crds.enabled=true \
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=$CERT_MANAGER_CLIENT_ID" \
    --set-string "podLabels.azure\.workload\.identity/use=true" \
    --wait --timeout 5m
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=120s
echo -e "${GREEN}✓ cert-manager installed${NC}"
echo ""

echo -e "${YELLOW}Applying the Let's Encrypt ClusterIssuer (Azure DNS DNS-01)...${NC}"
envsubst < "$MANIFESTS_DIR/cert-manager/cluster-issuer.yaml.tpl" > "$RENDERED_DIR/cluster-issuer.yaml"
kubectl apply -f "$RENDERED_DIR/cluster-issuer.yaml"
echo -e "${GREEN}✓ ClusterIssuer applied${NC}"
echo ""

echo -e "${YELLOW}Requesting the bookinfo gateway TLS certificate for ${BOOKINFO_FQDN}...${NC}"
envsubst < "$MANIFESTS_DIR/cert-manager/gateway-certificate.yaml.tpl" > "$RENDERED_DIR/gateway-certificate.yaml"
kubectl apply -f "$RENDERED_DIR/gateway-certificate.yaml"
echo -e "${GREEN}✓ Certificate requested (DNS-01 challenge may take a minute or two)${NC}"
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
# Ingress gateway (HTTPS via the cert-manager-issued certificate)
#############################################
echo -e "${YELLOW}Applying the Istio Gateway + VirtualService for productpage...${NC}"
envsubst < "$MANIFESTS_DIR/ingress/gateway.yaml.tpl" > "$RENDERED_DIR/gateway.yaml"
envsubst < "$MANIFESTS_DIR/ingress/virtualservice-productpage.yaml.tpl" > "$RENDERED_DIR/virtualservice-productpage.yaml"
kubectl apply -f "$RENDERED_DIR/gateway.yaml"
kubectl apply -f "$RENDERED_DIR/virtualservice-productpage.yaml"
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

if [ -n "${GATEWAY_IP:-}" ]; then
    echo -e "${YELLOW}Pointing ${BOOKINFO_FQDN} at ${GATEWAY_IP} in Azure DNS...${NC}"
    az network dns record-set a create \
        --resource-group "$DNS_ZONE_RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" \
        --name "$BOOKINFO_SUBDOMAIN" --ttl 300 --only-show-errors &>/dev/null || true
    az network dns record-set a add-record \
        --resource-group "$DNS_ZONE_RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" \
        --record-set-name "$BOOKINFO_SUBDOMAIN" --ipv4-address "$GATEWAY_IP" --only-show-errors >/dev/null
    echo -e "${GREEN}✓ A record updated${NC}"
else
    echo -e "${YELLOW}Gateway IP not ready - skipping DNS A record update. Re-run 'az network dns record-set a add-record' manually once it is.${NC}"
fi
echo ""

echo -e "${YELLOW}Waiting for the TLS certificate to become Ready (DNS-01 propagation)...${NC}"
kubectl wait --for=condition=Ready certificate/bookinfo-gateway-tls -n aks-istio-ingress --timeout=300s || \
    echo -e "${YELLOW}Certificate not Ready yet - check with: kubectl describe certificate bookinfo-gateway-tls -n aks-istio-ingress${NC}"
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${BLUE}Istio revision:${NC}        $ISTIO_REVISION"
if [ -n "${GATEWAY_IP:-}" ]; then
    echo -e "${BLUE}Bookinfo app:${NC}          https://${BOOKINFO_FQDN}/productpage (DNS/TLS may take a few minutes to propagate)"
    echo -e "${BLUE}Gateway IP:${NC}            $GATEWAY_IP"
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
