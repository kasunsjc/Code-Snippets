#!/bin/bash
# =============================================================================
# Demo 05 — Cleanup: Remove ingress vcluster, NGINX IC, and all host resources
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VCLUSTER_NAME="ingress"
VCLUSTER_NS="vc-ingress"
NGINX_NS="ingress-nginx"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Demo 05 — Cleanup                             ${NC}"
echo -e "${CYAN}================================================${NC}"

# Ensure we are on the host cluster context before cleanup
print_step "Disconnecting from vcluster (if connected)"
vcluster disconnect 2>/dev/null || true

print_step "Deleting vcluster '$VCLUSTER_NAME'"
info "Running vcluster delete — removes StatefulSet, Services, synced Ingresses..."
# vcluster delete: cleanly removes the vcluster and all its in-cluster resources.
# Ingress objects synced toHost (in vc-ingress namespace) are also removed.
# --delete-namespace: also removes the host namespace vc-ingress.
vcluster delete "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --delete-namespace 2>/dev/null || true
ok "vcluster '$VCLUSTER_NAME' deleted"

print_step "Removing namespace '$VCLUSTER_NS' (if still present)"
kubectl delete namespace "$VCLUSTER_NS" --ignore-not-found=true
ok "Namespace '$VCLUSTER_NS' deleted"

print_step "Uninstalling NGINX Ingress Controller"
# helm uninstall: removes the NGINX IC Helm release (Deployment, Service, etc.).
# The Azure Load Balancer public IP is released when the LoadBalancer Service is deleted.
if helm status ingress-nginx -n "$NGINX_NS" &>/dev/null; then
  info "Uninstalling Helm release 'ingress-nginx'..."
  helm uninstall ingress-nginx --namespace "$NGINX_NS"
  ok "NGINX Ingress Controller uninstalled"
else
  info "Helm release 'ingress-nginx' not found — skipping"
fi

info "Deleting namespace '$NGINX_NS'..."
kubectl delete namespace "$NGINX_NS" --ignore-not-found=true
ok "Namespace '$NGINX_NS' deleted"

print_step "Removing kubeconfig context"
kubectl config delete-context "$VCLUSTER_NAME" 2>/dev/null \
  && echo -e "${GREEN}  ✓ Deleted context '$VCLUSTER_NAME'${NC}" \
  || echo -e "${YELLOW}  → Context '$VCLUSTER_NAME' not found — skipping${NC}"

kubectl config delete-cluster "$VCLUSTER_NAME" 2>/dev/null \
  && echo -e "${GREEN}  ✓ Deleted cluster '$VCLUSTER_NAME'${NC}" \
  || echo -e "${YELLOW}  → Cluster '$VCLUSTER_NAME' not found — skipping${NC}"

kubectl config delete-user "$VCLUSTER_NAME" 2>/dev/null \
  && echo -e "${GREEN}  ✓ Deleted user '$VCLUSTER_NAME'${NC}" \
  || echo -e "${YELLOW}  → User '$VCLUSTER_NAME' not found — skipping${NC}"

echo ""
echo -e "${GREEN}Demo 05 cleanup complete.${NC}"
echo ""
echo -e "${YELLOW}  Note: The Azure Load Balancer public IP may take a few minutes${NC}"
echo -e "${YELLOW}  to be fully released after the ingress-nginx Service is deleted.${NC}"
echo ""
echo -e "${YELLOW}  Next: Demo 06 — Embedded etcd + HA${NC}"
echo "    cd ../06-etcd-datastore && ./setup-etcd-demo.sh"
echo ""

