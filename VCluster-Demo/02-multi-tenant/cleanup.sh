#!/bin/bash
# =============================================================================
# Demo 02 — Cleanup: Remove both tenant vclusters and all associated resources
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Demo 02 — Cleanup                             ${NC}"
echo -e "${CYAN}================================================${NC}"

# Ensure we are on the host cluster context before cleanup
print_step "Disconnecting from vcluster (if connected)"
vcluster disconnect 2>/dev/null || true

print_step "Deleting tenant vclusters"
for tenant in a b; do
  name="tenant-${tenant}"
  ns="vc-tenant-${tenant}"
  info "Deleting vcluster '$name' in namespace '$ns'..."
  # vcluster delete: removes the vcluster StatefulSet and associated resources.
  # --delete-namespace: also removes the host namespace and everything in it.
  vcluster delete "$name" \
    --namespace "$ns" \
    --delete-namespace 2>/dev/null || true
  ok "vcluster '$name' deleted"
done

print_step "Removing namespaces (if still present)"
# Belt-and-suspenders: ensure namespaces are gone even if vcluster delete
# did not remove them (e.g. if vclusters had already been partially deleted).
for ns in vc-tenant-a vc-tenant-b; do
  kubectl delete namespace "$ns" --ignore-not-found=true
  ok "Namespace '$ns' deleted"
done

print_step "Removing kubeconfig contexts"
# Remove both vcluster kubeconfig contexts, clusters, and users.
for name in tenant-a tenant-b; do
  kubectl config delete-context "$name" 2>/dev/null \
    && echo -e "${GREEN}  ✓ Deleted context '$name'${NC}" \
    || echo -e "${YELLOW}  → Context '$name' not found — skipping${NC}"

  kubectl config delete-cluster "$name" 2>/dev/null \
    && echo -e "${GREEN}  ✓ Deleted cluster '$name'${NC}" \
    || echo -e "${YELLOW}  → Cluster '$name' not found — skipping${NC}"

  kubectl config delete-user "$name" 2>/dev/null \
    && echo -e "${GREEN}  ✓ Deleted user '$name'${NC}" \
    || echo -e "${YELLOW}  → User '$name' not found — skipping${NC}"
done

print_step "Removing exported kubeconfig files"
# Clean up the scoped kubeconfig files exported to /tmp during the demo.
for f in /tmp/tenant-a-kubeconfig.yaml /tmp/tenant-b-kubeconfig.yaml; do
  if [[ -f "$f" ]]; then
    rm -f "$f"
    ok "Removed $f"
  else
    info "$f not found — skipping"
  fi
done

echo ""
echo -e "${GREEN}Demo 02 cleanup complete.${NC}"
echo ""
echo -e "${YELLOW}  Next: Demo 03 — Resource Limits & Isolation${NC}"
echo "    cd ../03-resource-limits && ./setup-limits.sh"
echo ""

