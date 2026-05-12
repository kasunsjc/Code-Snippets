#!/bin/bash
# =============================================================================
# Demo 03 — Resource Limits & Isolation
# =============================================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()  { echo -e "${GREEN}  ✓ $1${NC}"; }
info(){ echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Demo 03 — Resource Limits & Isolation    ${NC}"
echo -e "${CYAN}============================================${NC}"

# --------------------------------------------------
# Step 1 — Create namespace and apply host quota
# --------------------------------------------------
print_step "Step 1: Create namespace with ResourceQuota on the HOST"

info "Creating namespace vc-limits..."
kubectl create namespace vc-limits --dry-run=client -o yaml | kubectl apply -f -

info "Applying ResourceQuota and LimitRange to the host namespace..."
kubectl apply -f "$DEMO_DIR/host-namespace-quota.yaml" -n vc-limits

echo ""
echo -e "${YELLOW}  ResourceQuota in vc-limits:${NC}"
kubectl get resourcequota -n vc-limits
echo ""
echo -e "${YELLOW}  LimitRange in vc-limits:${NC}"
kubectl get limitrange -n vc-limits

# --------------------------------------------------
# Step 2 — Create vcluster with explicit resource requests
# --------------------------------------------------
print_step "Step 2: Create vcluster (must declare resources due to quota)"

info "Creating vcluster 'limits'..."
vcluster create limits \
  --namespace vc-limits \
  --values "$DEMO_DIR/vcluster-with-limits.yaml" \
  --connect=false

info "Waiting for vcluster to be ready..."
kubectl rollout status statefulset/limits --namespace vc-limits --timeout=180s
ok "vcluster 'limits' is running"

echo ""
echo -e "${YELLOW}  ResourceQuota usage after vcluster creation:${NC}"
kubectl describe resourcequota vcluster-quota -n vc-limits | grep -E "Resource|---|-"

# --------------------------------------------------
# Step 3 — Deploy workloads inside vcluster
# --------------------------------------------------
print_step "Step 3: Deploy workloads inside the vcluster"

info "Connecting to vcluster..."
vcluster connect limits --namespace vc-limits --update-current

info "Deploying test workloads..."
kubectl apply -f "$DEMO_DIR/workload-test.yaml"

info "Applying a LimitRange inside the vcluster..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: quota-test
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 128Mi
      defaultRequest:
        cpu: 50m
        memory: 64Mi
      max:
        cpu: "1"
        memory: 512Mi
EOF

kubectl rollout status deployment/well-behaved-app -n quota-test --timeout=120s
ok "well-behaved-app is running"

echo ""
echo -e "${YELLOW}  Pods inside vcluster:${NC}"
kubectl get pods -n quota-test

# --------------------------------------------------
# Step 4 — Try to exceed quota (expect failure)
# --------------------------------------------------
print_step "Step 4: Attempt to exceed quota (educational failure)"

info "Attempting to schedule a greedy pod (10 CPUs)..."
kubectl apply -f - <<'EOF' || true
apiVersion: v1
kind: Pod
metadata:
  name: greedy-pod
  namespace: quota-test
spec:
  containers:
    - name: greedy
      image: nginx:alpine
      resources:
        requests:
          cpu: "10"
          memory: 32Gi
EOF

sleep 5
echo ""
echo -e "${YELLOW}  greedy-pod status (should be Pending):${NC}"
kubectl get pod greedy-pod -n quota-test 2>/dev/null || echo "  Pod rejected at admission"
kubectl describe pod greedy-pod -n quota-test 2>/dev/null | grep -A3 "Events:" || true

info "Cleaning up greedy pod..."
kubectl delete pod greedy-pod -n quota-test --ignore-not-found

# --------------------------------------------------
# Step 5 — Check quota usage from host perspective
# --------------------------------------------------
print_step "Step 5: Platform engineer checks quota usage"

info "Disconnecting from vcluster..."
vcluster disconnect

echo ""
echo -e "${YELLOW}  ResourceQuota usage (host view):${NC}"
kubectl describe resourcequota vcluster-quota -n vc-limits

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}  Demo 03 complete!${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "  What you learned:"
echo "    • Host namespace ResourceQuota caps total vcluster resource usage"
echo "    • vcluster control plane must declare resources when a quota exists"
echo "    • LimitRange inside vcluster sets defaults for tenant workloads"
echo "    • Greedy pods are blocked at the scheduling/admission stage"
echo "    • Platform engineers can monitor quota usage from the host"
echo ""
echo -e "${YELLOW}  Cleanup:${NC}"
echo "    vcluster delete limits --namespace vc-limits --delete-namespace"
echo ""
echo -e "${YELLOW}  Next: Demo 04 — Custom Sync Configuration${NC}"
echo "    cd ../04-custom-sync && ./setup-sync.sh"
echo ""
