#!/bin/bash
# =============================================================================
# Demo 04 — Cleanup: Remove sync vcluster and all associated host resources
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VCLUSTER_NAME="sync"
VCLUSTER_NS="vc-sync"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Demo 04 — Cleanup                             ${NC}"
echo -e "${CYAN}================================================${NC}"

# Ensure we are on the host cluster context before cleanup
print_step "Disconnecting from vcluster (if connected)"
vcluster disconnect 2>/dev/null || true

print_step "Deleting vcluster '$VCLUSTER_NAME'"
info "Running vcluster delete — removes StatefulSet, Services, ConfigMaps, Secrets..."
# vcluster delete: cleanly removes the vcluster and all its in-cluster resources.
# Ingresses that were synced toHost will be removed as part of vcluster teardown.
# --delete-namespace: also removes the host namespace, including the shared ConfigMap
# and Secret that were created in Step 1 of the demo.
vcluster delete "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --delete-namespace 2>/dev/null || true
ok "vcluster '$VCLUSTER_NAME' deleted"

print_step "Removing namespace '$VCLUSTER_NS' (if still present)"
# Belt-and-suspenders: also removes any remaining synced Ingresses, shared ConfigMap,
# and shared Secret that were applied to the namespace during the demo setup.
kubectl delete namespace "$VCLUSTER_NS" --ignore-not-found=true
ok "Namespace '$VCLUSTER_NS' (and its shared ConfigMap/Secret) deleted"

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
echo -e "${GREEN}Demo 04 cleanup complete.${NC}"
echo ""
echo -e "${YELLOW}  Next: Demo 05 — Ingress & Networking${NC}"
echo "    cd ../05-ingress-networking && ./setup-ingress.sh"
echo ""

