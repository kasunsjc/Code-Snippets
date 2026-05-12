#!/bin/bash
# =============================================================================
# Demo 04 — Custom Sync Configuration
# =============================================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

print_step() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; echo ""; }
ok()  { echo -e "${GREEN}  ✓ $1${NC}"; }
info(){ echo -e "${YELLOW}  → $1${NC}"; }

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Demo 04 — Custom Sync Configuration      ${NC}"
echo -e "${CYAN}============================================${NC}"

# --------------------------------------------------
# Step 1 — Create namespace and host resources
# --------------------------------------------------
print_step "Step 1: Create namespace and host-level shared resources"

info "Creating namespace vc-sync..."
kubectl create namespace vc-sync --dry-run=client -o yaml | kubectl apply -f -

info "Creating shared ConfigMap on the HOST..."
kubectl apply -f "$DEMO_DIR/test-configmap.yaml"

info "Creating shared Secret on the HOST..."
kubectl apply -f "$DEMO_DIR/test-secret-host.yaml"

ok "Host resources created"
echo ""
echo -e "${YELLOW}  ConfigMaps in vc-sync (host):${NC}"
kubectl get configmap -n vc-sync

# --------------------------------------------------
# Step 2 — Create vcluster with extended sync
# --------------------------------------------------
print_step "Step 2: Create vcluster with extended sync config"

info "Creating vcluster 'sync'..."
vcluster create sync \
  --namespace vc-sync \
  --values "$DEMO_DIR/sync-values.yaml" \
  --connect=false

info "Waiting for vcluster to be ready..."
kubectl rollout status statefulset/sync --namespace vc-sync --timeout=180s
ok "vcluster 'sync' is running"

# --------------------------------------------------
# Step 3 — Connect and verify fromHost sync
# --------------------------------------------------
print_step "Step 3: Verify fromHost sync (host resources appear in vcluster)"

info "Connecting to vcluster..."
vcluster connect sync --namespace vc-sync --update-current

echo ""
echo -e "${YELLOW}  ConfigMaps in kube-system (inside vcluster):${NC}"
kubectl get configmap -n kube-system | grep -E "NAME|shared" || echo "  (may take a few seconds to sync)"

sleep 5

echo ""
echo -e "${YELLOW}  Checking for shared-platform-config in vcluster:${NC}"
kubectl get configmap shared-platform-config -n kube-system 2>/dev/null \
  && ok "shared-platform-config synced from host into vcluster!" \
  || echo -e "${YELLOW}  Still syncing — try: kubectl get cm -n kube-system${NC}"

echo ""
echo -e "${YELLOW}  IngressClasses visible inside vcluster (synced from host):${NC}"
kubectl get ingressclass 2>/dev/null || echo "  No IngressClasses on host yet (install nginx ingress first)"

echo ""
echo -e "${YELLOW}  StorageClasses visible inside vcluster (synced from host):${NC}"
kubectl get storageclass

# --------------------------------------------------
# Step 4 — Deploy an app with Ingress inside vcluster
# --------------------------------------------------
print_step "Step 4: Deploy an app with Ingress (tests toHost Ingress sync)"

info "Deploying echo-server with Ingress inside the vcluster..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: sync-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  namespace: sync-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
        - name: echo
          image: ealen/echo-server:latest
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: echo-server
  namespace: sync-test
spec:
  selector:
    app: echo
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-ingress
  namespace: sync-test
spec:
  ingressClassName: nginx
  rules:
    - host: echo.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: echo-server
                port:
                  number: 80
EOF

kubectl rollout status deployment/echo-server -n sync-test --timeout=120s
ok "echo-server deployed inside vcluster"

echo ""
echo -e "${YELLOW}  Ingress inside vcluster (virtual name):${NC}"
kubectl get ingress -n sync-test

# --------------------------------------------------
# Step 5 — Verify Ingress appeared on the HOST
# --------------------------------------------------
print_step "Step 5: Verify Ingress sync to host"

info "Disconnecting from vcluster..."
vcluster disconnect

echo ""
echo -e "${YELLOW}  Ingresses in vc-sync on the HOST (synced from vcluster):${NC}"
kubectl get ingress -n vc-sync

echo ""
echo "  Notice the ingress name is prefixed with the vcluster name on the host."
echo "  The host Ingress controller picks it up and routes traffic correctly."

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}  Demo 04 complete!${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "  What you learned:"
echo "    • fromHost sync: host ConfigMaps/Secrets appear inside vcluster"
echo "    • toHost sync: vcluster Ingresses are synced to the host namespace"
echo "    • IngressClass and StorageClass synced automatically from host"
echo "    • Label selectors control WHICH host resources get synced in"
echo ""
echo -e "${YELLOW}  Cleanup:${NC}"
echo "    vcluster delete sync --namespace vc-sync --delete-namespace"
echo ""
echo -e "${YELLOW}  Next: Demo 05 — Ingress & Networking${NC}"
echo "    cd ../05-ingress-networking && ./setup-ingress.sh"
echo ""
