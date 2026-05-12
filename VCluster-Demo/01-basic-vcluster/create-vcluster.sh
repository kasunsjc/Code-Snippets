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

# PURPOSE: Set up the host namespace where the vcluster control plane will run
info "Creating namespace '$VCLUSTER_NS'..."
# kubectl create namespace: creates a new Kubernetes namespace
# --dry-run=client: don't actually create, just validate client-side
# -o yaml: output the resource definition as YAML
# The YAML is piped to kubectl apply which idempotently creates it (safe to run multiple times)
# This pattern avoids "already exists" errors if namespace pre-exists
kubectl create namespace "$VCLUSTER_NS" --dry-run=client -o yaml | kubectl apply -f -

# PURPOSE: Create the virtual cluster inside the namespace
info "Creating vcluster '$VCLUSTER_NAME' with k3s distro..."
# vcluster create: creates a new virtual Kubernetes cluster
# $VCLUSTER_NAME: name of the virtual cluster (used for kubeconfig context and StatefulSet name)
# --namespace: host cluster namespace where the vcluster control plane StatefulSet will run
# --values: path to vcluster configuration file (specifies k3s distro, resources, sync settings)
# --connect=false: don't automatically update kubeconfig; we'll do it manually for learning purposes
vcluster create "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --values "$DEMO_DIR/vcluster-values.yaml" \
  --connect=false

ok "vcluster '$VCLUSTER_NAME' created in namespace '$VCLUSTER_NS'"

# --------------------------------------------------
# Step 2 — Wait for vcluster to be ready
# --------------------------------------------------
print_step "Step 2: Wait for vcluster to be ready"

# PURPOSE: Block until the vcluster control plane is fully operational
info "Waiting for vcluster StatefulSet to be available (may take ~60s)..."
# kubectl rollout status: waits for a deployment/statefulset to reach a stable state
# statefulset/$VCLUSTER_NAME: the vcluster control plane is deployed as a StatefulSet (ordered, named replicas)
# --timeout=180s: maximum time to wait; fails if not ready after 3 minutes
# StatefulSet ready means the vcluster control plane pod is running and the API server is accepting requests
kubectl rollout status statefulset/"$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --timeout=180s

ok "vcluster control plane is running"

# --------------------------------------------------
# Step 3 — Show host cluster perspective
# --------------------------------------------------
print_step "Step 3: Observe what the HOST cluster sees"

# PURPOSE: Demonstrate that the host cluster only sees the vcluster control plane pod
# The virtual cluster is just a pod running on the host cluster!
echo ""
echo -e "${YELLOW}  Pods in namespace '$VCLUSTER_NS' on the HOST:${NC}"
# kubectl get pods: list all pods in a namespace
# -n $VCLUSTER_NS: specify namespace (default is 'default')
# Shows the vcluster control plane pod (StatefulSet with name like 'basic-0')
kubectl get pods -n "$VCLUSTER_NS"

echo ""
echo -e "${YELLOW}  NOTE: The host only sees the vcluster control plane pod.${NC}"
echo -e "${YELLOW}        Workloads you deploy INSIDE the vcluster will also${NC}"
echo -e "${YELLOW}        appear here (as synced pods) but with mangled names.${NC}"

# --------------------------------------------------
# Step 4 — Connect to the vcluster
# --------------------------------------------------
print_step "Step 4: Connect to the vcluster"

# PURPOSE: Update local kubeconfig to point to the vcluster API server instead of host cluster
info "Connecting to vcluster '$VCLUSTER_NAME' (updates kubeconfig)..."
# vcluster connect: establishes connection to virtual cluster API server
# Downloads kubeconfig from the vcluster StatefulSet and merges it locally
# --update-current: modify the current kubeconfig context to point to the vcluster
# This allows subsequent kubectl commands to target the VIRTUAL cluster, not the host
vcluster connect "$VCLUSTER_NAME" \
  --namespace "$VCLUSTER_NS" \
  --update-current

ok "Connected — your kubectl context is now INSIDE the vcluster"
echo ""
# Display current context to confirm we're in the vcluster
# kubectl config current-context: shows active kubeconfig context (should be vcluster name)
kubectl config current-context

# --------------------------------------------------
# Step 5 — Explore the virtual cluster
# --------------------------------------------------
print_step "Step 5: Explore the virtual cluster"

# PURPOSE: Observe the clean slate inside the vcluster — isolated from host cluster
echo -e "${YELLOW}  Nodes visible inside the vcluster:${NC}"
# kubectl get nodes: list all worker nodes connected to THIS cluster's API server
# Inside the vcluster, there's only the vcluster host's nodes (synced from host)
# The actual pod scheduling happens on these nodes via sync mechanism
kubectl get nodes

echo ""
echo -e "${YELLOW}  Namespaces inside the vcluster (clean slate!):${NC}"
# kubectl get namespaces: list all namespaces IN THIS VCLUSTER
# The vcluster starts with default Kubernetes namespaces (default, kube-system, etc)
# but no custom namespaces from the host — full isolation achieved
kubectl get namespaces

# --------------------------------------------------
# Step 6 — Deploy a demo application inside vcluster
# --------------------------------------------------
print_step "Step 6: Deploy demo app inside the vcluster"

# PURPOSE: Deploy a workload inside the vcluster to demonstrate pod syncing
info "Applying demo-app.yaml..."
# kubectl apply -f: creates/updates resources from YAML file
# We're INSIDE the vcluster context, so this creates resources in the virtual cluster
# demo-app.yaml includes: namespace, deployment (nginx), service, and a verify-pod
kubectl apply -f "$DEMO_DIR/demo-app.yaml"

info "Waiting for deployment to roll out..."
# kubectl rollout status: wait until deployment has all replicas ready
# -n demo-app: the deployment is in the 'demo-app' namespace (created by demo-app.yaml)
# --timeout=120s: fail if not ready after 2 minutes
kubectl rollout status deployment/nginx-demo -n demo-app --timeout=120s

ok "nginx-demo is running inside the vcluster"

echo ""
echo -e "${YELLOW}  Pods inside the vcluster:${NC}"
# kubectl get pods: list pods IN THIS VCLUSTER
# The sync mechanism automatically syncs these pods to the host cluster's namespace
kubectl get pods -n demo-app

# --------------------------------------------------
# Step 7 — Test connectivity from inside vcluster
# --------------------------------------------------
print_step "Step 7: Test DNS and connectivity inside vcluster"

# PURPOSE: Demonstrate that the vcluster has its own DNS and networking layer
info "Waiting for verify-pod to be ready..."
# kubectl wait: block until a pod reaches Ready condition
# pod/verify-pod: the pod created by demo-app.yaml (curl client for testing)
# --for=condition=Ready: wait for the Ready condition to be True
kubectl wait pod/verify-pod -n demo-app --for=condition=Ready --timeout=60s

echo ""
echo -e "${YELLOW}  Calling nginx-demo.demo-app.svc.cluster.local from verify-pod:${NC}"
# kubectl exec: execute a command INSIDE a container
# -n demo-app: target the pod in demo-app namespace
# verify-pod: the pod to exec into
# curl: test HTTP connectivity to the nginx service (FQDN: service.namespace.svc.cluster.local)
# -s: silent (no progress bar)
# -o /dev/null: discard response body
# -w "HTTP status: %{http_code}\n": output only HTTP status code
kubectl exec -n demo-app verify-pod -- \
  curl -s -o /dev/null -w "HTTP status: %{http_code}\n" http://nginx-demo.demo-app.svc.cluster.local

# --------------------------------------------------
# Step 8 — Switch back to host context and compare
# --------------------------------------------------
print_step "Step 8: Switch back to host and compare"

# PURPOSE: Show how the host cluster sees the synced resources
info "Disconnecting from vcluster..."
# vcluster disconnect: revert kubeconfig to previous context (host cluster)
# This switches kubectl back to target the host cluster, not the vcluster
vcluster disconnect

echo ""
echo -e "${YELLOW}  Pods in namespace '$VCLUSTER_NS' on the HOST after app deployment:${NC}"
# kubectl get pods: NOW listing pods on the HOST cluster in the vcluster namespace
# The nginx pods from inside the vcluster are SYNCED here (synced from vcluster to host)
# They have mangled names because the vcluster prefixes them to avoid conflicts
kubectl get pods -n "$VCLUSTER_NS"
echo ""
echo -e "${YELLOW}  Notice: nginx pods appear here too (synced from vcluster) but the${NC}"
echo -e "${YELLOW}  'demo-app' namespace does NOT exist on the host:${NC}"
# kubectl get namespace demo-app: try to get the namespace on the HOST cluster
# This will fail (2>/dev/null silences the error) because namespaces are isolated in vcluster
# Only the pod CONTAINERS are synced; the namespace abstraction is not
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
