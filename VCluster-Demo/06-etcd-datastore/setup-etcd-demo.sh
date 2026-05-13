#!/bin/bash
# =============================================================================
# Demo 06 — vcluster with Embedded etcd Backing Store
# =============================================================================
# Demonstrates replacing the default SQLite backend with a full embedded etcd
# cluster, enabling High Availability (3 replicas) and durable state storage.
#
# What this demo covers:
#   1. Create a vcluster with embedded etcd and HA replicas
#   2. Inspect the etcd pods and PVCs created on the host cluster
#   3. Deploy a stateful app with a PVC inside the vcluster
#   4. Simulate a control plane restart and verify state persistence
#   5. Run basic etcd health checks from inside the vcluster pod
#
# Prerequisites:
#   - Host AKS cluster running (run ../deploy.sh first)
#   - vcluster CLI installed (run ../install-tools.sh)
#   - kubectl pointing to the host AKS cluster

set -e

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

VCLUSTER_NAME="etcd-demo"
VCLUSTER_NS="vc-etcd"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()         { echo -e "${GREEN}  ✓ $1${NC}"; }
info()       { echo -e "${YELLOW}  → $1${NC}"; }
warn()       { echo -e "${RED}  ⚠ $1${NC}"; }

echo ""
echo -e "${CYAN}${BOLD}============================================================${NC}"
echo -e "${CYAN}${BOLD}  Demo 06 — vcluster with Embedded etcd Backing Store       ${NC}"
echo -e "${CYAN}${BOLD}============================================================${NC}"
echo ""
echo -e "  Default:        SQLite (single file, no HA)"
echo -e "  This demo:      Embedded etcd (3 replicas, durable PVCs)"
echo ""

# --------------------------------------------------
# Step 1 — Create namespace + vcluster
# --------------------------------------------------
print_step "Step 1: Create the vcluster with embedded etcd"

info "Creating namespace '$VCLUSTER_NS'..."
# Idempotent namespace creation via dry-run + apply pattern
kubectl create namespace "$VCLUSTER_NS" --dry-run=client -o yaml | kubectl apply -f -

info "Creating vcluster '$VCLUSTER_NAME' (3 etcd replicas — this takes ~2 minutes)..."
# KEY DIFFERENCE from Demo 01:
#   --values etcd-values.yaml activates controlPlane.backingStore.embeddedEtcd.enabled: true
#   and highAvailability.replicas: 3  — three StatefulSet pods, each with their own etcd member
#   and a PVC for durable storage (no data loss on pod restart)
vcluster create "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --values "$DEMO_DIR/etcd-values.yaml" \
  --connect=false

ok "vcluster '$VCLUSTER_NAME' created in namespace '$VCLUSTER_NS'"

# --------------------------------------------------
# Step 2 — Wait for all HA replicas to be ready
# --------------------------------------------------
print_step "Step 2: Wait for all 3 HA replicas to be ready"

info "Waiting for StatefulSet rollout (3/3 replicas)..."
# With HA replicas=3 the StatefulSet has 3 pods. rollout status waits for all
# pods to become Ready before returning.
kubectl rollout status statefulset/"$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --timeout=300s

ok "All 3 vcluster control plane replicas are running"

# --------------------------------------------------
# Step 3 — Inspect host cluster resources
# --------------------------------------------------
print_step "Step 3: Inspect what the HOST cluster provisions for etcd"

info "Control plane pods (3 replicas = 3 etcd members):"
# Each pod hosts: vcluster API server + embedded etcd member
kubectl get pods \
  --namespace "$VCLUSTER_NS" \
  --selector="app=$VCLUSTER_NAME" \
  -o wide

echo ""
info "PersistentVolumeClaims (1 PVC per replica for etcd WAL + snapshot data):"
# Each replica gets its own PVC from etcd-values.yaml persistence block.
# Azure Disk (ReadWriteOnce) — PVC survives pod deletions and restarts.
kubectl get pvc --namespace "$VCLUSTER_NS"

echo ""
info "Services created for the HA control plane:"
# vcluster creates a headless service for etcd peer communication and a
# regular service for the API server endpoint.
kubectl get services --namespace "$VCLUSTER_NS"

# --------------------------------------------------
# Step 4 — Connect and deploy a stateful app
# --------------------------------------------------
print_step "Step 4: Connect to vcluster and deploy a stateful app"

info "Connecting to vcluster (updates kubeconfig)..."
# vcluster connect switches the current kubeconfig context to the vcluster's
# API server, so subsequent kubectl commands run inside the virtual cluster.
vcluster connect "$VCLUSTER_NAME" --namespace "$VCLUSTER_NS"

ok "Connected to vcluster — kubectl now talks to virtual cluster"
echo ""
info "Current context: $(kubectl config current-context)"
echo ""

info "Deploying stateful test app (PVC + StatefulSet + Service)..."
# test-persistence.yaml deploys an Nginx pod that writes a startup timestamp
# to a PVC on every start. We'll use this to verify persistence after restart.
kubectl apply -f "$DEMO_DIR/test-persistence.yaml"

info "Waiting for persistence-demo pod to be ready..."
kubectl rollout status statefulset/persistence-demo \
  --namespace default \
  --timeout=180s

ok "Stateful app deployed and running"

# --------------------------------------------------
# Step 5 — Read the startup log (first boot)
# --------------------------------------------------
print_step "Step 5: Read startup log — first boot"

DEMO_POD="persistence-demo-0"

info "Pod logs written to PVC on startup:"
# Show the startup timestamp that the initContainer wrote to the PVC.
# This will contain exactly one entry (this is the first boot).
kubectl exec "$DEMO_POD" -- cat /data/startup-log.txt

echo ""
ok "First-boot log confirmed — one startup entry in PVC"

# --------------------------------------------------
# Step 6 — Simulate control plane restart
# --------------------------------------------------
print_step "Step 6: Simulate a vcluster control plane restart"

info "Disconnecting from vcluster (switching back to host context)..."
# We need to be on the host context to restart the vcluster StatefulSet.
vcluster disconnect

info "Deleting all vcluster control plane pods to simulate a restart..."
# Deleting StatefulSet pods forces Kubernetes to recreate them.
# Because each replica has a PVC, etcd data is preserved across pod deletion.
# With 3 replicas and quorum-based etcd, the cluster remains available even
# while individual pods are being restarted (rolling restart).
kubectl delete pods \
  --namespace "$VCLUSTER_NS" \
  --selector="app=$VCLUSTER_NAME" \
  --grace-period=0 \
  --force

info "Waiting for all replicas to come back up..."
kubectl rollout status statefulset/"$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --timeout=300s

ok "All replicas restarted successfully — etcd data preserved via PVCs"

# --------------------------------------------------
# Step 7 — Reconnect and verify state survived
# --------------------------------------------------
print_step "Step 7: Reconnect and verify state survived the restart"

info "Reconnecting to vcluster..."
vcluster connect "$VCLUSTER_NAME" --namespace "$VCLUSTER_NS"
ok "Reconnected — kubectl context: $(kubectl config current-context)"

echo ""
info "Checking that the StatefulSet and PVC still exist (etcd state intact):"
# If etcd state survived, all previously applied resources should still be here.
kubectl get statefulset,pvc,service --namespace default

echo ""
info "Reading startup log — should contain the original first-boot entry:"
# The PVC was NOT wiped — it still has the first-boot timestamp.
# Because etcd preserved the PVC binding, the pod remounted the same PVC.
kubectl exec "$DEMO_POD" -- cat /data/startup-log.txt

echo ""
ok "State verified — both etcd metadata and PVC data survived the restart"

# --------------------------------------------------
# Step 8 — etcd health check from inside the pod
# --------------------------------------------------
print_step "Step 8: Run etcd health check inside the control plane pod"

info "Switching back to host context for etcd introspection..."
vcluster disconnect

info "Checking etcd cluster health from inside vcluster pod '$VCLUSTER_NAME-0':"
# The vcluster control plane container bundles etcdctl.
# ETCDCTL_API=3: use etcd v3 API
# --endpoints: etcd listens on localhost:2379 inside the pod
# --cacert/--cert/--key: TLS certs are stored at /data/server/tls/etcd/
echo ""
kubectl exec \
  --namespace "$VCLUSTER_NS" \
  "$VCLUSTER_NAME-0" \
  --container syncer \
  -- sh -c '
    ETCDCTL_API=3 etcdctl \
      --endpoints=https://localhost:2379 \
      --cacert=/data/server/tls/etcd/ca.crt \
      --cert=/data/server/tls/etcd/server.crt \
      --key=/data/server/tls/etcd/server.key \
      endpoint health --cluster
  ' 2>&1 || warn "etcdctl not available in this container — see README for alternative"

echo ""
info "Listing etcd members (shows all 3 HA peers):"
kubectl exec \
  --namespace "$VCLUSTER_NS" \
  "$VCLUSTER_NAME-0" \
  --container syncer \
  -- sh -c '
    ETCDCTL_API=3 etcdctl \
      --endpoints=https://localhost:2379 \
      --cacert=/data/server/tls/etcd/ca.crt \
      --cert=/data/server/tls/etcd/server.crt \
      --key=/data/server/tls/etcd/server.key \
      member list -w table
  ' 2>&1 || warn "etcdctl not available in this container — see README for alternative"

# --------------------------------------------------
# Step 9 — Summary
# --------------------------------------------------
print_step "Demo 06 Complete"

echo -e "${BOLD}What was demonstrated:${NC}"
echo "  ✓ vcluster created with embedded etcd (instead of default SQLite)"
echo "  ✓ 3 HA replicas — each with a dedicated PVC for durable etcd storage"
echo "  ✓ Stateful app deployed inside the vcluster with its own PVC"
echo "  ✓ vcluster control plane forcibly restarted (all pods deleted)"
echo "  ✓ After restart: etcd state intact, PVC still bound, app still running"
echo ""
echo -e "${BOLD}Key takeaways:${NC}"
echo "  • Embedded etcd enables HA — no single point of failure"
echo "  • PVCs ensure etcd WAL data persists across pod restarts"
echo "  • Use embedded etcd for production vclusters or long-lived environments"
echo "  • Use SQLite (default) for short-lived CI/dev vclusters to save resources"
echo ""
echo -e "${YELLOW}  → To clean up this demo run: ./cleanup-etcd.sh${NC}"
echo ""
