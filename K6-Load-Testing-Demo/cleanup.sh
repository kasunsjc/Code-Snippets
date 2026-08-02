#!/bin/bash
# ==============================================================
# K6 Load Testing Demo — Cleanup Script
# ==============================================================
set -euo pipefail

RESOURCE_GROUP="rg-k6-demo-dev"

if ! command -v az &>/dev/null; then
  echo "ERROR: 'az' is not installed or not in PATH."
  exit 1
fi

echo "=================================================="
echo "  K6 Load Testing Demo — Cleanup"
echo "=================================================="
echo "This will permanently delete resource group: $RESOURCE_GROUP"
echo ""
# Require explicit 'yes' to avoid accidental deletion in demos.
read -r -p "Are you sure? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo "Deleting resource group $RESOURCE_GROUP..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "Deletion initiated. Resources will be removed in the background."
