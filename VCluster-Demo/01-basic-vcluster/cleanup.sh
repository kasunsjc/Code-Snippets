#!/bin/bash
# =============================================================================
# Demo 01 — Cleanup: Remove basic vcluster and all associated host resources
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VCLUSTER_NAME="basic"
VCLUSTER_NS="vc-basic"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Demo 01 — Cleanup                             ${NC}"
echo -e "${CYAN}================================================${NC}"

# Ensure we are on the host cluster context before cleanup
print_step "Disconnecting from vcluster (if connected)"
# vcluster disconnect: restores the previous kubeconfig context (host cluster).
# Safe to run even if not currently connected to a vcluster.
vcluster disconnect 2>/dev/null || true

print_step "Deleting vcluster '$VCLUSTER_NAME'"
info "Running vcluster delete — removes StatefulSet, Services, ConfigMaps, Secrets..."
# vcluster delete: cleanly removes the vcluster and all its in-cluster resources.
# --namespace: required to locate the correct vcluster StatefulSet.
# --delete-namespace: also removes the host namespace and all resources within it.
vcluster delete "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --delete-namespace 2>/dev/null || true
ok "vcluster '$VCLUSTER_NAME' deleted"

print_step "Removing namespace '$VCLUSTER_NS' (if still present)"
# Belt-and-suspenders: ensure the namespace is gone even if vcluster delete
# did not remove it (e.g. if the vcluster had already been partially deleted).
kubectl delete namespace "$VCLUSTER_NS" --ignore-not-found=true
ok "Namespace '$VCLUSTER_NS' deleted"

print_step "Removing kubeconfig context"
# Remove the vcluster kubeconfig context, cluster, and user entries to keep
# the kubeconfig file clean after teardown.
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
echo -e "${GREEN}Demo 01 cleanup complete.${NC}"
echo ""
echo -e "${YELLOW}  Next: Demo 02 — Multi-Tenant vClusters${NC}"
echo "    cd ../02-multi-tenant && ./setup-tenants.sh"
echo ""

