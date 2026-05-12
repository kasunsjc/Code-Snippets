#!/bin/bash
# =============================================================================
# Install NGINX Ingress Controller on the host AKS cluster
# Run this ONCE before Demo 05.
# =============================================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()  { echo -e "${GREEN}  ✓ $1${NC}"; }
info(){ echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}Installing NGINX Ingress Controller on the host AKS cluster${NC}"
echo ""

if ! command -v helm &> /dev/null; then
  echo "Helm is required. Run ../install-tools.sh first."
  exit 1
fi

info "Adding ingress-nginx Helm repository..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

info "Installing ingress-nginx (this may take ~2 minutes)..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set controller.replicaCount=2 \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=128Mi \
  --wait \
  --timeout 5m

ok "ingress-nginx installed"

info "Waiting for LoadBalancer IP assignment..."
for i in {1..30}; do
  EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  [[ -n "$EXTERNAL_IP" ]] && break
  echo "  Waiting... ($i/30)"
  sleep 10
done

if [[ -z "$EXTERNAL_IP" ]]; then
  echo "LoadBalancer IP not yet assigned. Check: kubectl get svc -n ingress-nginx"
  exit 1
fi

ok "LoadBalancer IP: $EXTERNAL_IP"
echo ""
echo -e "${CYAN}  For DNS-less testing, use nip.io:${NC}"
echo "    Host: echo.${EXTERNAL_IP}.nip.io"
echo "    curl http://echo.${EXTERNAL_IP}.nip.io"
echo ""
echo -e "${YELLOW}  Remember this IP for Demo 05:${NC}"
echo "    EXTERNAL_IP=$EXTERNAL_IP"
echo ""
