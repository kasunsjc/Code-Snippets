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

# Helm/kubectl cleanup is unnecessary: the AKS API server is private, and
# terraform destroy above already removes the cluster (and everything on it).
rm -rf "$SCRIPT_DIR/.rendered"
echo "Cleanup completed."
