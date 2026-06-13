#!/bin/bash
# ==============================================================
# AKS KEDA Demo — Terraform Deployment Script
# ==============================================================
set -euo pipefail

RESOURCE_GROUP="rg-aks-keda-demo"
LOCATION="northeurope"
K8S_NAMESPACE="keda-demo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TF_VARS_FILE="$TF_DIR/terraform.tfvars"

echo "=================================================="
echo "  AKS KEDA Demo — Terraform Deployment"
echo "=================================================="
echo "Resource Group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Terraform dir  : $TF_DIR"
echo ""

for cmd in az kubectl terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

echo "Checking Azure CLI login..."
az account show --output none || { echo "ERROR: Not logged in to Azure. Run 'az login'."; exit 1; }

echo ""
echo "Retrieving current user Object ID for role assignments..."
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [[ -z "$USER_OBJECT_ID" ]]; then
  echo "  Warning: Could not retrieve user Object ID. Optional role assignments will be skipped."
fi

echo ""
echo "[1/6] Initializing Terraform..."
terraform -chdir="$TF_DIR" init

echo ""
echo "[2/6] Applying Terraform infrastructure..."
if [[ -f "$TF_VARS_FILE" ]]; then
  terraform -chdir="$TF_DIR" apply \
    -auto-approve \
    -var-file="$TF_VARS_FILE" \
    -var="resource_group_name=$RESOURCE_GROUP" \
    -var="location=$LOCATION" \
    -var="user_object_id=${USER_OBJECT_ID:-}"
else
  terraform -chdir="$TF_DIR" apply \
    -auto-approve \
    -var="resource_group_name=$RESOURCE_GROUP" \
    -var="location=$LOCATION" \
    -var="user_object_id=${USER_OBJECT_ID:-}"
fi

echo ""
echo "[3/6] Reading Terraform outputs..."
tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

AKS_NAME=$(tf_out aks_cluster_name)
STORAGE_ACCOUNT=$(tf_out storage_account_name)
EH_NAMESPACE=$(tf_out eventhub_namespace_name)
EH_NAME=$(tf_out eventhub_name)
OIDC_ISSUER=$(tf_out oidc_issuer_url)
GRAFANA_URL=$(tf_out grafana_url)
PROMETHEUS_ENDPOINT=$(tf_out prometheus_query_endpoint)
ACR_LOGIN_SERVER=$(tf_out acr_login_server)

echo "  AKS cluster          : $AKS_NAME"
echo "  Storage account      : $STORAGE_ACCOUNT"
echo "  Event Hub namespace  : $EH_NAMESPACE"
echo "  Event Hub            : $EH_NAME"
echo "  OIDC issuer          : $OIDC_ISSUER"
echo "  Grafana URL          : $GRAFANA_URL"
echo "  Prometheus endpoint  : $PROMETHEUS_ENDPOINT"
echo "  ACR login server     : $ACR_LOGIN_SERVER"

echo ""
echo "[4/6] Fetching AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --overwrite-existing

echo ""
echo "[5/6] Verifying KEDA add-on is running..."
kubectl wait deployment/keda-operator \
  --namespace kube-system \
  --for=condition=Available \
  --timeout=300s 2>/dev/null || true
kubectl get pods -n kube-system | grep keda || true

echo ""
echo "[6/6] Creating namespace and K8s secrets..."
kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

STORAGE_CS=$(az storage account show-connection-string \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query connectionString \
  --output tsv)

kubectl create secret generic azure-storage-secret \
  --namespace "$K8S_NAMESPACE" \
  --from-literal=connection-string="$STORAGE_CS" \
  --dry-run=client -o yaml | kubectl apply -f -

EH_CS=$(az eventhubs namespace authorization-rule keys list \
  --resource-group "$RESOURCE_GROUP" \
  --namespace-name "$EH_NAMESPACE" \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString \
  --output tsv)

kubectl create secret generic azure-eventhub-secret \
  --namespace "$K8S_NAMESPACE" \
  --from-literal=eventhub-connection-string="$EH_CS" \
  --from-literal=storage-connection-string="$STORAGE_CS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=================================================="
echo "  Deployment Complete!"
echo "=================================================="
echo "AKS cluster            : $AKS_NAME"
echo "Resource group         : $RESOURCE_GROUP"
echo "K8s namespace          : $K8S_NAMESPACE"
echo "Azure Managed Grafana  : $GRAFANA_URL"
echo "Prometheus endpoint    : $PROMETHEUS_ENDPOINT"
echo "ACR login server       : $ACR_LOGIN_SERVER"
