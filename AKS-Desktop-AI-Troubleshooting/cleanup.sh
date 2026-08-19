#!/bin/bash
set -euo pipefail

RESOURCE_GROUP="rg-aks-desktop-ai-demo"

echo "Deleting resource group: $RESOURCE_GROUP..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "Resource group deletion started."
