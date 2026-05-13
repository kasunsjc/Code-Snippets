#!/bin/bash
# =============================================================================
# Demo 06 — Cleanup: Remove etcd vcluster and all associated host resources
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VCLUSTER_NAME="etcd-demo"
VCLUSTER_NS="vc-etcd"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Demo 06 — Cleanup                             ${NC}"
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
# This does NOT delete the PVCs by default — they must be removed separately.
vcluster delete "$VCLUSTER_NAME" --namespace "$VCLUSTER_NS" 2>/dev/null || true
ok "vcluster deleted"

print_step "Removing PersistentVolumeClaims (etcd data volumes)"
info "Deleting PVCs in namespace '$VCLUSTER_NS'..."
# PVCs are not removed by vcluster delete to prevent accidental data loss.
# We explicitly remove them here since this is a demo teardown.
kubectl delete pvc --namespace "$VCLUSTER_NS" --all --ignore-not-found=true
ok "PVCs deleted"

print_step "Removing namespace '$VCLUSTER_NS'"
# Deleting the namespace removes all remaining resources (ConfigMaps, Secrets, etc.)
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
echo -e "${GREEN}Demo 06 cleanup complete.${NC}"
echo ""
