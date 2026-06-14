#!/bin/bash
# ==============================================================
# AKS KEDA Demo — Terraform Deployment Script
# ==============================================================
set -euo pipefail

RESOURCE_GROUP="rg-aks-keda-demo"
LOCATION="northeurope"
K8S_NAMESPACE="keda-demo"
DEMO="none"
IMAGE_TAG="latest"
PLATFORM="linux/amd64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TF_VARS_FILE="$TF_DIR/terraform.tfvars"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
SAMPLE_APPS_DIR="$SCRIPT_DIR/sample-apps"

usage() {
  cat <<EOF
Usage: ./deploy.sh [options]

Options:
  --demo <none|eventhub|storage-queue|prometheus|all>  Optional demo workload deployment.
  --image-tag <tag>                                     Image tag used when building/pushing demo images.
  --help                                                Show this help.

Examples:
  ./deploy.sh
  ./deploy.sh --demo eventhub --image-tag v1
  ./deploy.sh --demo prometheus
  ./deploy.sh --demo all --image-tag latest
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --demo requires a value."
        usage
        exit 1
      fi
      DEMO="$2"
      shift 2
      ;;
    --image-tag)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --image-tag requires a value."
        usage
        exit 1
      fi
      IMAGE_TAG="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument '$1'"
      usage
      exit 1
      ;;
  esac
done

if [[ "$DEMO" != "none" && "$DEMO" != "eventhub" && "$DEMO" != "storage-queue" && "$DEMO" != "prometheus" && "$DEMO" != "all" ]]; then
  echo "ERROR: Invalid --demo value '$DEMO'. Expected one of: none, eventhub, storage-queue, prometheus, all."
  exit 1
fi

echo "=================================================="
echo "  AKS KEDA Demo — Terraform Deployment"
echo "=================================================="
echo "Resource Group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Terraform dir  : $TF_DIR"
echo "Demo deploy    : $DEMO"
echo "Image tag      : $IMAGE_TAG"
echo ""

for cmd in az kubectl terraform docker; do
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
PROMETHEUS_WI_CLIENT_ID=$(tf_out prometheus_workload_identity_client_id)
ACR_LOGIN_SERVER=$(tf_out acr_login_server)
CHECKPOINT_CONTAINER_NAME=$(tf_out checkpoint_container_name)

echo "  AKS cluster              : $AKS_NAME"
echo "  Storage account          : $STORAGE_ACCOUNT"
echo "  Event Hub namespace      : $EH_NAMESPACE"
echo "  Event Hub                : $EH_NAME"
echo "  OIDC issuer              : $OIDC_ISSUER"
echo "  Grafana URL              : $GRAFANA_URL"
echo "  Prometheus endpoint      : $PROMETHEUS_ENDPOINT"
echo "  Prometheus WI client ID  : $PROMETHEUS_WI_CLIENT_ID"
echo "  ACR login server         : $ACR_LOGIN_SERVER"
echo "  Checkpoint container     : $CHECKPOINT_CONTAINER_NAME"

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

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\\\&/g'
}

apply_secret_manifest_with_values() {
  local file_path="$1"
  local escaped_storage_cs
  local escaped_eventhub_cs

  escaped_storage_cs=$(escape_sed_replacement "$STORAGE_CS")
  escaped_eventhub_cs=$(escape_sed_replacement "${EH_CS:-}")

  sed \
    -e "s|{{ STORAGE_CONNECTION_STRING }}|$escaped_storage_cs|g" \
    -e "s|{{ EVENTHUB_CONNECTION_STRING }}|$escaped_eventhub_cs|g" \
    "$file_path" | kubectl apply -n "$K8S_NAMESPACE" -f -
}

STORAGE_CS=$(az storage account show-connection-string \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query connectionString \
  --output tsv)

EH_CS=$(az eventhubs namespace authorization-rule keys list \
  --resource-group "$RESOURCE_GROUP" \
  --namespace-name "$EH_NAMESPACE" \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString \
  --output tsv)

echo "  Applying secret manifests with runtime values..."
apply_secret_manifest_with_values "$SCENARIOS_DIR/01-storage-queue/00-secret.yaml"
apply_secret_manifest_with_values "$SCENARIOS_DIR/05-eventhub/00-secret.yaml"

if [[ "$DEMO" != "none" ]]; then
  apply_manifest_with_substitution() {
    local file_path="$1"
    sed \
      -e "s|{{ ACR_LOGIN_SERVER }}|$ACR_LOGIN_SERVER|g" \
      -e "s|{{ CHECKPOINT_CONTAINER_NAME }}|$CHECKPOINT_CONTAINER_NAME|g" \
      -e "s|{{ IMAGE_TAG }}|$IMAGE_TAG|g" \
      -e "s|{{ PROMETHEUS_QUERY_ENDPOINT }}|$PROMETHEUS_ENDPOINT|g" \
      -e "s|{{ PROMETHEUS_WORKLOAD_IDENTITY_CLIENT_ID }}|$PROMETHEUS_WI_CLIENT_ID|g" \
      "$file_path" | kubectl apply -n "$K8S_NAMESPACE" -f -
  }

  # Only build and push images for demos that require custom container images.
  # The Prometheus demo uses python:3.12-slim directly — no image build needed.
  if [[ "$DEMO" == "eventhub" || "$DEMO" == "storage-queue" || "$DEMO" == "all" ]]; then
    echo ""
    echo "[7/8] Building and pushing demo images ($PLATFORM)..."

    ACR_NAME=$(echo "$ACR_LOGIN_SERVER" | cut -d'.' -f1)
    az acr login --name "$ACR_NAME"

    build_and_push_image() {
      local image_name="$1"
      local context_dir="$2"

      echo "  Building and pushing $image_name:$IMAGE_TAG"
      docker buildx build \
        --platform "$PLATFORM" \
        --tag "$ACR_LOGIN_SERVER/$image_name:$IMAGE_TAG" \
        --push \
        "$context_dir"
    }

    if [[ "$DEMO" == "eventhub" || "$DEMO" == "all" ]]; then
      build_and_push_image "eventhub-producer" "$SAMPLE_APPS_DIR/eventhub-producer"
      build_and_push_image "eventhub-consumer" "$SAMPLE_APPS_DIR/eventhub-consumer"
    fi

    if [[ "$DEMO" == "storage-queue" || "$DEMO" == "all" ]]; then
      build_and_push_image "storage-queue-producer" "$SAMPLE_APPS_DIR/storage-queue-producer"
      build_and_push_image "storage-queue-consumer" "$SAMPLE_APPS_DIR/storage-queue-consumer"
    fi
  else
    echo ""
    echo "[7/8] Skipping image build (demo '$DEMO' uses public images only)."
  fi

  echo ""
  echo "[8/8] Applying demo manifests..."

  if [[ "$DEMO" == "eventhub" || "$DEMO" == "all" ]]; then
    echo "  Deploying Event Hub demo..."
    apply_manifest_with_substitution "$SCENARIOS_DIR/05-eventhub/01-deployment.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/05-eventhub/02-trigger-auth.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/05-eventhub/03-scaled-object.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/05-eventhub/05-producer-deployment.yaml"
  fi

  if [[ "$DEMO" == "storage-queue" || "$DEMO" == "all" ]]; then
    echo "  Deploying Storage Queue demo..."
    apply_manifest_with_substitution "$SCENARIOS_DIR/01-storage-queue/01-deployment.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/01-storage-queue/02-trigger-auth.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/01-storage-queue/03-scaled-object.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/01-storage-queue/05-producer-deployment.yaml"
  fi

  if [[ "$DEMO" == "prometheus" || "$DEMO" == "all" ]]; then
    echo "  Deploying Prometheus demo..."
    apply_manifest_with_substitution "$SCENARIOS_DIR/03-prometheus/00-trigger-auth.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/03-prometheus/01-sample-app.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/03-prometheus/02-service.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/03-prometheus/03-scaled-object.yaml"
    apply_manifest_with_substitution "$SCENARIOS_DIR/03-prometheus/04-load-generator-job.yaml"
  fi
fi

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
echo ""
echo "Infrastructure and authentication prerequisites are ready."
if [[ "$DEMO" == "none" ]]; then
  echo "Application image build/push and Kubernetes manifest deployment were skipped."
elif [[ "$DEMO" == "prometheus" ]]; then
  echo "Demo '$DEMO' was deployed (no custom image build required)."
else
  echo "Demo '$DEMO' was built, pushed to ACR, and deployed."
fi
echo ""
echo "Created secrets:"
kubectl get secret azure-storage-secret -n "$K8S_NAMESPACE" >/dev/null 2>&1 && echo "  - azure-storage-secret" || true
kubectl get secret azure-eventhub-secret -n "$K8S_NAMESPACE" >/dev/null 2>&1 && echo "  - azure-eventhub-secret" || true
