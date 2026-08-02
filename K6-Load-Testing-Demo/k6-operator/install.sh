#!/bin/bash
# ==============================================================
# K6 Load Testing Demo — k6 Operator Install
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "--- Installing k6 Operator ---"

helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

helm upgrade --install k6-operator grafana/k6-operator \
  --namespace k6-operator \
  --create-namespace \
  --wait \
  --timeout 5m

echo "  k6 Operator installed."
echo "  Test results are available via: kubectl logs -n k6-tests -l k6_cr=<name> -f"
