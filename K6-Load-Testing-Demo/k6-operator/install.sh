#!/bin/bash
# ==============================================================
# K6 Load Testing Demo — k6 Operator Install
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "--- Installing k6 Operator ---"

# The chart is published in the 'grafana' Helm repo; this does not deploy Grafana itself.
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

helm upgrade --install k6-operator grafana/k6-operator \
  --namespace k6-operator \
  --wait \
  --timeout 5m

echo "  k6 Operator installed."
echo "  Test results are available via: kubectl logs -n k6-tests -l k6_cr=<name> -f"
