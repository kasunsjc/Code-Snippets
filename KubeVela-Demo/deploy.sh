#!/bin/bash
# ==============================================================
# KubeVela on AKS - Terraform Deployment Script
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TF_VARS_FILE="$TF_DIR/terraform.tfvars"

TF_VAR_ARGS=()
if [[ -f "$TF_VARS_FILE" ]]; then
  TF_VAR_ARGS+=("-var-file=$TF_VARS_FILE")
fi

echo "=================================================="
echo "  KubeVela on AKS - Deployment"
echo "=================================================="

for command in az terraform kubectl kubelogin helm; do
  if ! command -v "$command" &>/dev/null; then
    echo "ERROR: '$command' is not installed or not in PATH."
    exit 1
  fi
done

echo "Checking Azure CLI login..."
az account show --output none || {
  echo "ERROR: Not logged in to Azure. Run 'az login'."
  exit 1
}

echo ""
echo "[1/5] Initializing and validating Terraform..."
terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" validate

echo ""
echo "[2/5] Applying AKS infrastructure..."
terraform -chdir="$TF_DIR" apply -auto-approve "${TF_VAR_ARGS[@]}"

tf_output() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

RESOURCE_GROUP=$(tf_output resource_group_name)
CLUSTER_NAME=$(tf_output cluster_name)

echo ""
echo "[3/5] Fetching AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

echo ""
echo "[4/5] Waiting for AKS nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl get nodes

echo ""
echo "[5/5] Installing KubeVela..."
helm repo add kubevela https://kubevela.github.io/charts
helm repo update kubevela
helm upgrade --install kubevela kubevela/vela-core \
  --namespace vela-system \
  --create-namespace \
  --wait \
  --timeout 10m
kubectl rollout status deployment/kubevela-vela-core -n vela-system --timeout=5m

echo ""
echo "=================================================="
echo "  KubeVela is ready"
echo "=================================================="
echo "Cluster        : $CLUSTER_NAME"
echo "Resource group : $RESOURCE_GROUP"
echo "Namespace      : vela-system"
echo ""
echo "Explore with: kubectl get application -A"