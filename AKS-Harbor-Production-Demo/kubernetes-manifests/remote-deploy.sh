#!/bin/bash
# Runs on the jumpbox (inside the VNet) via SSH over an Azure Bastion tunnel.
# Everything here is already-rendered by deploy.sh - no envsubst/gettext needed.
set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="$PAYLOAD_DIR/kubeconfig"

GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }

info "Installing Helm repositories..."
helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo add harbor https://helm.goharbor.io --force-update >/dev/null
helm repo update >/dev/null

info "Installing Traefik..."
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --version "41.5.0" \
  --wait --timeout 5m

info "Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "1.21.2" \
  --set crds.enabled=true \
  --wait --timeout 5m

info "Creating Harbor namespace and base manifests..."
kubectl apply -f "$PAYLOAD_DIR/namespace.yaml"
kubectl apply -f "$PAYLOAD_DIR/cluster-issuer.yaml"

info "Applying storage class and secret sync resources..."
kubectl apply -f "$PAYLOAD_DIR/storageclass-azurefile-zrs-nfs.yaml"
kubectl apply -f "$PAYLOAD_DIR/secretproviderclass.yaml"
kubectl apply -f "$PAYLOAD_DIR/keyvault-secret-sync.yaml"

info "Applying Harbor audit-log forwarder (must be Ready before Harbor installs)..."
kubectl apply -f "$PAYLOAD_DIR/audit-log-forwarder.yaml"
kubectl rollout status deployment/harbor-audit-forwarder -n harbor --timeout=120s

info "Deploying Harbor..."
helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  -f "$PAYLOAD_DIR/harbor-values.yaml" \
  --version "1.19.2" \
  --wait --timeout 10m

info "Applying Harbor ingress and certificate manifests..."
kubectl apply -f "$PAYLOAD_DIR/harbor-certificate.yaml"
kubectl apply -f "$PAYLOAD_DIR/harbor-ingress-route.yaml"

info "Harbor deployment completed with Entra ID OIDC configuration."
