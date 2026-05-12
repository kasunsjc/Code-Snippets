#!/bin/bash
# =============================================================================
# Demo 01 — Basic vcluster
# =============================================================================
# Creates a single vcluster, deploys a demo app inside it, and walks through
# the key concepts: isolation, kubeconfig switching, and host-cluster view.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

VCLUSTER_NAME="basic"
VCLUSTER_NS="vc-basic"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Demo 01 — Getting Started with vcluster  ${NC}"
echo -e "${CYAN}============================================${NC}"

# --------------------------------------------------
# Step 1 — Create namespace + vcluster
# --------------------------------------------------
print_step "Step 1: Create the vcluster"

info "Creating namespace '$VCLUSTER_NS'..."
kubectl create namespace "$VCLUSTER_NS" --dry-run=client -o yaml | kubectl apply -f -

info "Creating vcluster '$VCLUSTER_NAME' with k3s distro..."
vcluster create "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --values "$DEMO_DIR/vcluster-values.yaml" \
  --connect=false    # we'll connect manually in the next step

ok "vcluster '$VCLUSTER_NAME' created in namespace '$VCLUSTER_NS'"

# --------------------------------------------------
# Step 2 — Wait for vcluster to be ready
# --------------------------------------------------
print_step "Step 2: Wait for vcluster to be ready"

info "Waiting for vcluster StatefulSet to be available (may take ~60s)..."
kubectl rollout status statefulset/"$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --timeout=180s

ok "vcluster control plane is running"

# --------------------------------------------------
# Step 3 — Show host cluster perspective
# --------------------------------------------------
print_step "Step 3: Observe what the HOST cluster sees"

echo ""
echo -e "${YELLOW}  Pods in namespace '$VCLUSTER_NS' on the HOST:${NC}"
kubectl get pods -n "$VCLUSTER_NS"

echo ""
echo -e "${YELLOW}  NOTE: The host only sees the vcluster control plane pod.${NC}"
echo -e "${YELLOW}        Workloads you deploy INSIDE the vcluster will also${NC}"
echo -e "${YELLOW}        appear here (as synced pods) but with mangled names.${NC}"

# --------------------------------------------------
# Step 4 — Connect to the vcluster
# --------------------------------------------------
print_step "Step 4: Connect to the vcluster"

info "Connecting to vcluster '$VCLUSTER_NAME' (updates kubeconfig)..."
vcluster connect "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --update-current

ok "Connected — your kubectl context is now INSIDE the vcluster"
echo ""
kubectl config current-context

# --------------------------------------------------
# Step 5 — Explore the virtual cluster
# --------------------------------------------------
print_step "Step 5: Explore the virtual cluster"

echo -e "${YELLOW}  Nodes visible inside the vcluster:${NC}"
kubectl get nodes

echo ""
echo -e "${YELLOW}  Namespaces inside the vcluster (clean slate!):${NC}"
kubectl get namespaces

# --------------------------------------------------
# Step 6 — Deploy a demo application inside vcluster
# --------------------------------------------------
print_step "Step 6: Deploy demo app inside the vcluster"

info "Applying demo-app.yaml..."
kubectl apply -f "$DEMO_DIR/demo-app.yaml"

info "Waiting for deployment to roll out..."
kubectl rollout status deployment/nginx-demo -n demo-app --timeout=120s

ok "nginx-demo is running inside the vcluster"

echo ""
echo -e "${YELLOW}  Pods inside the vcluster:${NC}"
kubectl get pods -n demo-app

# --------------------------------------------------
# Step 7 — Test connectivity from inside vcluster
# --------------------------------------------------
print_step "Step 7: Test DNS and connectivity inside vcluster"

info "Waiting for verify-pod to be ready..."
kubectl wait pod/verify-pod -n demo-app --for=condition=Ready --timeout=60s

echo ""
echo -e "${YELLOW}  Calling nginx-demo.demo-app.svc.cluster.local from verify-pod:${NC}"
kubectl exec -n demo-app verify-pod -- \
  curl -s -o /dev/null -w "HTTP status: %{http_code}\n" http://nginx-demo.demo-app.svc.cluster.local

# --------------------------------------------------
# Step 8 — Switch back to host context and compare
# --------------------------------------------------
print_step "Step 8: Switch back to host and compare"

info "Disconnecting from vcluster..."
vcluster disconnect

echo ""
echo -e "${YELLOW}  Pods in namespace '$VCLUSTER_NS' on the HOST after app deployment:${NC}"
kubectl get pods -n "$VCLUSTER_NS"
echo ""
echo -e "${YELLOW}  Notice: nginx pods appear here too (synced from vcluster) but the${NC}"
echo -e "${YELLOW}  'demo-app' namespace does NOT exist on the host:${NC}"
kubectl get namespace demo-app 2>/dev/null || echo -e "${GREEN}  ✓ Namespace 'demo-app' is invisible on the host — isolation works!${NC}"

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}  Demo 01 complete!${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "  What you learned:"
echo "    • How to create a vcluster with a custom config"
echo "    • How to connect/disconnect using the vcluster CLI"
echo "    • The difference between host and virtual cluster views"
echo "    • How pod syncing works (virtual → host namespace)"
echo "    • Namespace isolation — demo-app exists only inside vcluster"
echo ""
echo -e "${YELLOW}  Cleanup for this demo only:${NC}"
echo "    vcluster delete $VCLUSTER_NAME --namespace $VCLUSTER_NS --delete-namespace"
echo ""
echo -e "${YELLOW}  Continue to Demo 02 — Multi-Tenant Vclusters:${NC}"
echo "    cd ../02-multi-tenant && ./setup-tenants.sh"
echo ""
