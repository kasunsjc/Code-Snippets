#!/bin/bash
# ==============================================================
# K6 Load Testing Demo — Deployment Script
# ==============================================================
set -euo pipefail

RESOURCE_GROUP="rg-k6-demo-dev"
LOCATION="northeurope"
CLUSTER_NAME="aks-k6-demo"
DEPLOYMENT_NAME="k6-demo-deployment"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "  K6 Load Testing Demo — Deployment"
echo "=================================================="
echo "Resource Group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Cluster Name   : $CLUSTER_NAME"
echo ""

# ========== Prerequisite checks ==========

for cmd in az kubectl helm; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

echo "Checking Azure CLI login..."
az account show --output none || { echo "ERROR: Not logged in. Run 'az login'."; exit 1; }

# ========== Resource Group ==========

echo ""
echo "[1/5] Creating resource group: $RESOURCE_GROUP..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table

# ========== Bicep Deployment ==========

echo ""
echo "[2/5] Deploying AKS cluster..."

USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [[ -z "$USER_OBJECT_ID" ]]; then
  echo "  Warning: Could not retrieve user Object ID. Admin role assignment will be skipped."
fi

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters "$SCRIPT_DIR/main.bicepparam" \
  --parameters userId="$USER_OBJECT_ID" \
  --output table

AKS_NAME=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT_NAME" \
  --query 'properties.outputs.aksClusterName.value' -o tsv)

# ========== AKS Credentials ==========

echo ""
echo "[3/5] Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --overwrite-existing

# ========== Sample Target App ==========

echo ""
echo "[4/5] Deploying go-httpbin target app..."
kubectl apply -f "$SCRIPT_DIR/sample-app/kubernetes-manifests/"
kubectl rollout status deployment/httpbin -n demo-apps --timeout=120s

# ========== k6 Operator ==========

echo ""
echo "[5/5] Installing k6 Operator..."
bash "$SCRIPT_DIR/k6-operator/install.sh"

# ========== Summary ==========

echo ""
echo "=================================================="
echo "  Deployment Complete"
echo "=================================================="
echo "AKS Cluster : $AKS_NAME"
echo ""
echo "Run a test scenario:"
echo "  kubectl apply -f scenarios/01-smoke-test/"
echo "  kubectl get testrun -n k6-tests -w"
echo "  kubectl logs -n k6-tests -l k6_cr=smoke-test -f"
echo ""
echo "Available scenarios:"
for dir in "$SCRIPT_DIR"/scenarios/*/; do
  echo "  kubectl apply -f ${dir}"
done
