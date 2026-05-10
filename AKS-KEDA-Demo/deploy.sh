#!/bin/bash
# ==============================================================
# AKS KEDA Demo — Infrastructure Deployment Script
# ==============================================================
# Deploys:
#   - AKS cluster with KEDA add-on enabled
#   - Azure Storage Account + Queue    (Scenario 01)
#   - Azure Service Bus Namespace + Queue  (Scenario 02)
#   - Kubernetes namespace 'keda-demo'
#   - K8s Secrets for scenarios 01 & 02
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
# ==============================================================
set -euo pipefail

# ---- Configuration ----
RESOURCE_GROUP="rg-aks-keda-demo"
LOCATION="australiaeast"
DEPLOYMENT_NAME="aks-keda-deployment"
K8S_NAMESPACE="keda-demo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "  AKS KEDA Demo — Deployment"
echo "=================================================="
echo "Resource Group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo ""

# ---- Prerequisites check ----
for cmd in az kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

echo "Checking Azure CLI login..."
az account show --output none || { echo "ERROR: Not logged in to Azure. Run 'az login'."; exit 1; }

# ---- Get current user Object ID ----
echo ""
echo "Retrieving current user Object ID for role assignments..."
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [[ -z "$USER_OBJECT_ID" ]]; then
  echo "  Warning: Could not retrieve user Object ID. Grafana Admin and AKS RBAC roles will not be assigned."
else
  echo "  User Object ID: $USER_OBJECT_ID"
fi

# ---- Create Resource Group ----
echo ""
echo "[1/7] Creating resource group: $RESOURCE_GROUP..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output table

# ---- Deploy Bicep ----
echo ""
echo "[2/7] Deploying AKS cluster with KEDA add-on and Azure Managed Prometheus..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters "$SCRIPT_DIR/main.bicepparam" \
  --parameters userId="${USER_OBJECT_ID:-}" \
  --output table

# ---- Read Outputs ----
echo ""
echo "[3/7] Reading deployment outputs..."
get_output() {
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --query "properties.outputs.$1.value" \
    --output tsv
}

AKS_NAME=$(get_output aksClusterName)
STORAGE_ACCOUNT=$(get_output storageAccountName)
SB_NAMESPACE=$(get_output serviceBusNamespaceName)
OIDC_ISSUER=$(get_output oidcIssuerUrl)
GRAFANA_URL=$(get_output grafanaUrl)
PROMETHEUS_ENDPOINT=$(get_output prometheusQueryEndpoint)

echo "  AKS cluster          : $AKS_NAME"
echo "  Storage account      : $STORAGE_ACCOUNT"
echo "  Service Bus          : $SB_NAMESPACE"
echo "  OIDC issuer          : $OIDC_ISSUER"
echo "  Grafana URL          : $GRAFANA_URL"
echo "  Prometheus endpoint  : $PROMETHEUS_ENDPOINT"

# ---- Get AKS Credentials ----
echo ""
echo "[4/7] Fetching AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --overwrite-existing

# ---- Verify KEDA Add-on ----
echo ""
echo "[5/7] Verifying KEDA add-on is running..."
echo "  Waiting for KEDA pods in kube-system..."
kubectl wait deployment/keda-operator \
  --namespace kube-system \
  --for=condition=Available \
  --timeout=300s 2>/dev/null || \
kubectl wait deployment/keda-admission \
  --namespace kube-system \
  --for=condition=Available \
  --timeout=300s 2>/dev/null || \
echo "  Note: KEDA pods may still be starting up. Run: kubectl get pods -n kube-system | grep keda"

kubectl get pods -n kube-system | grep keda || true

# ---- Create Kubernetes Namespace ----
echo ""
echo "[6/7] Creating Kubernetes namespace: $K8S_NAMESPACE..."
kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ---- Create K8s Secrets ----
echo ""
echo "[7/7] Creating Kubernetes secrets for scenarios 01 & 02..."

# Scenario 01 — Azure Storage Queue connection string
echo "  Fetching Storage Account connection string..."
STORAGE_CS=$(az storage account show-connection-string \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query connectionString \
  --output tsv)

kubectl create secret generic azure-storage-secret \
  --namespace "$K8S_NAMESPACE" \
  --from-literal=connection-string="$STORAGE_CS" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "  ✔ Secret 'azure-storage-secret' applied."

# Scenario 02 — Service Bus connection string
echo "  Fetching Service Bus connection string..."
SB_CS=$(az servicebus namespace authorization-rule keys list \
  --resource-group "$RESOURCE_GROUP" \
  --namespace-name "$SB_NAMESPACE" \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString \
  --output tsv)

kubectl create secret generic azure-servicebus-secret \
  --namespace "$K8S_NAMESPACE" \
  --from-literal=connection-string="$SB_CS" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "  ✔ Secret 'azure-servicebus-secret' applied."

# ---- Summary ----
echo ""
echo "=================================================="
echo "  Deployment Complete!"
echo "=================================================="
echo ""
echo "AKS cluster            : $AKS_NAME"
echo "Resource group         : $RESOURCE_GROUP"
echo "K8s namespace          : $K8S_NAMESPACE"
echo ""
echo "Azure Managed Grafana  : $GRAFANA_URL"
echo "Prometheus endpoint    : $PROMETHEUS_ENDPOINT"
echo ""
echo "KEDA pods:"
kubectl get pods -n kube-system -l app=keda-operator --no-headers 2>/dev/null \
  | awk '{print "  "$1, $3}' || true
echo ""
echo "Next steps — run a scenario:"
echo ""
echo "  # Scenario 01 — Azure Storage Queue"
echo "  kubectl apply -f scenarios/01-storage-queue/01-deployment.yaml -n $K8S_NAMESPACE"
echo "  kubectl apply -f scenarios/01-storage-queue/02-trigger-auth.yaml -n $K8S_NAMESPACE"
echo "  kubectl apply -f scenarios/01-storage-queue/03-scaled-object.yaml -n $K8S_NAMESPACE"
echo "  kubectl apply -f scenarios/01-storage-queue/04-producer-job.yaml  -n $K8S_NAMESPACE"
echo ""
echo "  # Scenario 02 — Azure Service Bus"
echo "  kubectl apply -f scenarios/02-service-bus/01-deployment.yaml -n $K8S_NAMESPACE"
echo "  kubectl apply -f scenarios/02-service-bus/02-trigger-auth.yaml -n $K8S_NAMESPACE"
echo "  kubectl apply -f scenarios/02-service-bus/03-scaled-object.yaml -n $K8S_NAMESPACE"
echo "  kubectl apply -f scenarios/02-service-bus/04-producer-job.yaml  -n $K8S_NAMESPACE"
echo ""
echo "  # Scenario 03 — Cron"
echo "  kubectl apply -f scenarios/03-cron/ -n $K8S_NAMESPACE"
echo ""
echo "  # Scenario 04 — Prometheus (Azure Managed Prometheus)"
echo "  # 1. Update serverAddress in 03-scaled-object.yaml with: $PROMETHEUS_ENDPOINT"
echo "  # 2. Populate bearer token:"
echo "  #    TOKEN=\$(az account get-access-token --resource https://prometheus.monitor.azure.com --query accessToken -o tsv)"
echo "  #    kubectl create secret generic azure-managed-prometheus-secret -n $K8S_NAMESPACE --from-literal=bearerToken=\"\$TOKEN\" --dry-run=client -o yaml | kubectl apply -f -"
echo "  kubectl apply -f scenarios/04-prometheus/ -n $K8S_NAMESPACE"
echo ""
echo "  # Scenario 05 — CPU / Memory"
echo "  kubectl apply -f scenarios/05-cpu-memory/ -n $K8S_NAMESPACE"
echo ""
echo "  # Open Grafana to observe KEDA scaling"
echo "  echo \"Open: $GRAFANA_URL\""
