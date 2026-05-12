#!/bin/bash
# =============================================================================
# Demo 02 — Multi-Tenant vClusters
# =============================================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Demo 02 — Multi-Tenant vClusters         ${NC}"
echo -e "${CYAN}============================================${NC}"

# --------------------------------------------------
# Step 1 — Create both tenant vclusters
# --------------------------------------------------
print_step "Step 1: Create Team Alpha and Team Beta vclusters"

for tenant in a b; do
  ns="vc-tenant-${tenant}"
  name="tenant-${tenant}"
  info "Creating namespace $ns..."
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -

  info "Creating vcluster $name..."
  vcluster create "$name" \
    --namespace "$ns" \
    --values "$DEMO_DIR/tenant-${tenant}-values.yaml" \
    --connect=false
  ok "vcluster $name created"
done

echo ""
info "Waiting for both vclusters to be ready..."
kubectl rollout status statefulset/tenant-a --namespace vc-tenant-a --timeout=180s
kubectl rollout status statefulset/tenant-b --namespace vc-tenant-b --timeout=180s
ok "Both vclusters are running"

# --------------------------------------------------
# Step 2 — List all vclusters
# --------------------------------------------------
print_step "Step 2: Verify both vclusters (platform engineer view)"

echo -e "${YELLOW}  All vclusters:${NC}"
vcluster list

echo ""
echo -e "${YELLOW}  Host pods in vc-tenant-a:${NC}"
kubectl get pods -n vc-tenant-a

echo ""
echo -e "${YELLOW}  Host pods in vc-tenant-b:${NC}"
kubectl get pods -n vc-tenant-b

# --------------------------------------------------
# Step 3 — Deploy Team Alpha workloads
# --------------------------------------------------
print_step "Step 3: Team Alpha deploys their app"

info "Connecting to Team Alpha's vcluster..."
vcluster connect tenant-a --namespace vc-tenant-a --update-current

info "Deploying Team Alpha's app..."
kubectl apply -f "$DEMO_DIR/tenant-a-app.yaml"
kubectl rollout status deployment/alpha-frontend -n team-alpha --timeout=120s
ok "Team Alpha's frontend is running"

echo ""
echo -e "${YELLOW}  Team Alpha sees:${NC}"
kubectl get all -n team-alpha

echo ""
echo -e "${YELLOW}  Can Team Alpha see Team Beta's namespace on host?${NC}"
kubectl get namespace vc-tenant-b 2>/dev/null \
  && echo -e "${RED}  ISOLATION FAILURE — this should not be visible!${NC}" \
  || echo -e "${GREEN}  ✓ Team Beta's namespace is invisible — isolation works!${NC}"

info "Disconnecting from Team Alpha..."
vcluster disconnect

# --------------------------------------------------
# Step 4 — Deploy Team Beta workloads
# --------------------------------------------------
print_step "Step 4: Team Beta deploys their app"

info "Connecting to Team Beta's vcluster..."
vcluster connect tenant-b --namespace vc-tenant-b --update-current

info "Deploying Team Beta's app..."
kubectl apply -f "$DEMO_DIR/tenant-b-app.yaml"
kubectl rollout status deployment/beta-api -n team-beta --timeout=120s
ok "Team Beta's API is running"

echo ""
echo -e "${YELLOW}  Team Beta sees:${NC}"
kubectl get all -n team-beta

echo ""
echo -e "${YELLOW}  Can Team Beta see Team Alpha's resources?${NC}"
kubectl get namespace team-alpha 2>/dev/null \
  && echo -e "${RED}  ISOLATION FAILURE${NC}" \
  || echo -e "${GREEN}  ✓ Team Alpha's resources are invisible to Team Beta!${NC}"

info "Disconnecting from Team Beta..."
vcluster disconnect

# --------------------------------------------------
# Step 5 — Export scoped kubeconfigs
# --------------------------------------------------
print_step "Step 5: Export scoped kubeconfigs for each team"

vcluster connect tenant-a \
  --namespace vc-tenant-a \
  --update-current=false \
  --kube-config /tmp/tenant-a-kubeconfig.yaml
ok "Team Alpha kubeconfig exported to /tmp/tenant-a-kubeconfig.yaml"

vcluster connect tenant-b \
  --namespace vc-tenant-b \
  --update-current=false \
  --kube-config /tmp/tenant-b-kubeconfig.yaml
ok "Team Beta kubeconfig exported to /tmp/tenant-b-kubeconfig.yaml"

echo ""
echo -e "${YELLOW}  Verify Team Alpha kubeconfig works:${NC}"
KUBECONFIG=/tmp/tenant-a-kubeconfig.yaml kubectl get nodes

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}  Demo 02 complete!${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "  What you learned:"
echo "    • Two teams share the same host AKS cluster"
echo "    • Each team has complete Kubernetes isolation"
echo "    • Platform engineers can see all synced pods"
echo "    • Scoped kubeconfigs give teams self-service access"
echo ""
echo -e "${YELLOW}  Cleanup:${NC}"
echo "    vcluster delete tenant-a --namespace vc-tenant-a --delete-namespace"
echo "    vcluster delete tenant-b --namespace vc-tenant-b --delete-namespace"
echo ""
echo -e "${YELLOW}  Next: Demo 03 — Resource Limits & Isolation${NC}"
echo "    cd ../03-resource-limits && ./setup-limits.sh"
echo ""
