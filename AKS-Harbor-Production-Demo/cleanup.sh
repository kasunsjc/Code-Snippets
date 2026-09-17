#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

read -r -p "This will destroy the Harbor production demo resources in Azure. Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

if [[ -d "$TF_DIR" ]]; then
  terraform -chdir="$TF_DIR" destroy -auto-approve || true
fi

helm uninstall harbor -n harbor >/dev/null 2>&1 || true
helm uninstall traefik -n traefik >/dev/null 2>&1 || true
helm uninstall cert-manager -n cert-manager >/dev/null 2>&1 || true
kubectl delete namespace harbor --ignore-not-found >/dev/null 2>&1 || true
kubectl delete namespace traefik --ignore-not-found >/dev/null 2>&1 || true
kubectl delete namespace cert-manager --ignore-not-found >/dev/null 2>&1 || true

rm -rf "$SCRIPT_DIR/.rendered"
echo "Cleanup completed."
