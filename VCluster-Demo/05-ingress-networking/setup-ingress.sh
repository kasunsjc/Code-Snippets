#!/bin/bash
# =============================================================================
# Demo 05 — Ingress & Networking
# =============================================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()  { echo -e "${GREEN}  ✓ $1${NC}"; }
info(){ echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Demo 05 — Ingress & Networking           ${NC}"
echo -e "${CYAN}============================================${NC}"

# --------------------------------------------------
# Step 1 — Check / install NGINX Ingress Controller
# --------------------------------------------------
print_step "Step 1: Verify NGINX Ingress Controller"

if ! helm status ingress-nginx -n ingress-nginx &> /dev/null; then
  info "NGINX Ingress Controller not found — installing..."
  bash "$DEMO_DIR/install-nginx-ingress.sh"
else
  ok "NGINX Ingress Controller already installed"
fi

EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -z "$EXTERNAL_IP" ]]; then
  echo -e "${RED}  LoadBalancer IP not yet assigned. Wait and re-run.${NC}"
  exit 1
fi

ok "External IP: $EXTERNAL_IP"
HOST="echo.${EXTERNAL_IP}.nip.io"
info "Demo hostname: $HOST"

# --------------------------------------------------
# Step 2 — Create vcluster
# --------------------------------------------------
print_step "Step 2: Create vcluster with Ingress sync"

info "Creating namespace vc-ingress..."
kubectl create namespace vc-ingress --dry-run=client -o yaml | kubectl apply -f -

info "Creating vcluster 'ingress'..."
vcluster create ingress \
  --namespace vc-ingress \
  --values "$DEMO_DIR/ingress-values.yaml" \
  --connect=false

info "Waiting for vcluster to be ready..."
kubectl rollout status statefulset/ingress --namespace vc-ingress --timeout=180s
ok "vcluster 'ingress' is running"

# --------------------------------------------------
# Step 3 — Deploy app with Ingress inside vcluster
# --------------------------------------------------
print_step "Step 3: Deploy app with Ingress inside the vcluster"

info "Connecting to vcluster..."
vcluster connect ingress --namespace vc-ingress --update-current

info "Deploying echo-server with Ingress (host: $HOST)..."
sed "s/REPLACE_WITH_HOST/$HOST/g" "$DEMO_DIR/ingress-app.yaml" | kubectl apply -f -

kubectl rollout status deployment/echo-server -n ingress-test --timeout=120s
ok "echo-server deployed inside vcluster"

echo ""
echo -e "${YELLOW}  Ingress inside vcluster:${NC}"
kubectl get ingress -n ingress-test

echo ""
echo -e "${YELLOW}  IngressClasses visible inside vcluster (synced from host):${NC}"
kubectl get ingressclass

# --------------------------------------------------
# Step 4 — Verify Ingress on host
# --------------------------------------------------
print_step "Step 4: Verify Ingress was synced to host"

info "Disconnecting from vcluster..."
vcluster disconnect

echo ""
echo -e "${YELLOW}  Ingresses on the HOST in vc-ingress namespace:${NC}"
kubectl get ingress -n vc-ingress

echo ""
echo -e "${YELLOW}  Services on the HOST in vc-ingress namespace (synced):${NC}"
kubectl get service -n vc-ingress | grep echo

# --------------------------------------------------
# Step 5 — Test end-to-end HTTP access
# --------------------------------------------------
print_step "Step 5: Test end-to-end HTTP access"

info "Waiting a few seconds for Ingress to be picked up by NGINX IC..."
sleep 10

echo ""
echo -e "${YELLOW}  Testing: curl http://$HOST${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://$HOST" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "HTTP $HTTP_CODE — Traffic flowing through host Ingress to vcluster pod!"
else
  echo -e "${YELLOW}  HTTP $HTTP_CODE — (May need more time; try manually: curl http://$HOST)${NC}"
fi

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}  Demo 05 complete!${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "  What you learned:"
echo "    • NGINX Ingress Controller on host serves vcluster Ingresses"
echo "    • Ingress resources synced from vcluster → host namespace"
echo "    • IngressClass synced from host → vcluster (fromHost)"
echo "    • Traffic path: Internet → Azure LB → NGINX IC → synced pod"
echo ""
echo "  Test manually:"
echo "    curl http://$HOST"
echo ""
echo -e "${YELLOW}  Cleanup:${NC}"
echo "    vcluster delete ingress --namespace vc-ingress --delete-namespace"
echo "    helm uninstall ingress-nginx -n ingress-nginx"
echo "    kubectl delete namespace ingress-nginx"
echo ""
echo -e "${YELLOW}  Full cleanup (all demos + AKS cluster):${NC}"
echo "    cd .. && ./cleanup.sh"
echo ""
