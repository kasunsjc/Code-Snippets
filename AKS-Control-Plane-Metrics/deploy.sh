#!/bin/bash
# ==============================================================================
# AKS Control Plane Metrics demo - deploy
# ------------------------------------------------------------------------------
# Usage:
#   ./deploy.sh                    # Terraform enables control plane metrics
#   ./deploy.sh --enable-with-cli  # Terraform deploys without it, then the
#                                  # script enables it with 'az aks update'
#   ./deploy.sh --skip-load        # Do not start the API server load generator
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
K8S_DIR="$SCRIPT_DIR/k8s"

ENABLE_WITH_CLI=false
SKIP_LOAD=false

# Grafana dashboard gallery IDs for AKS control plane metrics
DASHBOARD_IDS=("20331" "20330") # Kubernetes / API Server, Kubernetes / ETCD

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "\n${BLUE}==> $1${NC}"; }

usage() {
  sed -n '3,10p' "$0"
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enable-with-cli) ENABLE_WITH_CLI=true ;;
      --skip-load) SKIP_LOAD=true ;;
      -h | --help) usage ;;
      *)
        print_error "Unknown option: $1"
        usage
        ;;
    esac
    shift
  done
}

check_prerequisites() {
  print_step "Checking prerequisites"
  local missing=0
  for tool in az terraform kubectl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      print_error "$tool is not installed."
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 1

  if ! az account show >/dev/null 2>&1; then
    print_error "Not logged in to Azure. Run 'az login' first."
    exit 1
  fi

  # 'az grafana' commands come from the amg extension
  az extension add --name amg --upgrade --only-show-errors >/dev/null 2>&1 || true

  print_message "Subscription: $(az account show --query name -o tsv)"
}

deploy_infrastructure() {
  print_step "Deploying infrastructure with Terraform"

  USER_OBJECT_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")"
  if [[ -z "$USER_OBJECT_ID" ]]; then
    print_warning "Could not resolve the signed-in user. Grafana Admin role will not be assigned."
  fi

  local tf_enable_cp="true"
  if [[ "$ENABLE_WITH_CLI" == "true" ]]; then
    tf_enable_cp="false"
    print_message "Control plane metrics will be enabled later with the Azure CLI."
  fi

  terraform -chdir="$TF_DIR" init -upgrade -input=false
  terraform -chdir="$TF_DIR" apply -auto-approve -input=false \
    -var "user_object_id=$USER_OBJECT_ID" \
    -var "enable_control_plane_metrics=$tf_enable_cp"

  RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
  GRAFANA_NAME="$(terraform -chdir="$TF_DIR" output -raw grafana_name)"
  GRAFANA_ENDPOINT="$(terraform -chdir="$TF_DIR" output -raw grafana_endpoint)"
}

get_credentials() {
  print_step "Fetching AKS credentials"
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
  kubectl get nodes -o wide
}

enable_control_plane_metrics_cli() {
  if [[ "$ENABLE_WITH_CLI" != "true" ]]; then
    return
  fi
  print_step "Enabling control plane metrics with the Azure CLI"
  az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --enable-control-plane-metrics \
    --only-show-errors \
    --output none
}

verify_control_plane_metrics() {
  print_step "Verifying the Azure Monitor profile"
  az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --query "azureMonitorProfile.metrics" -o json

  local cp_enabled
  cp_enabled="$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --query "azureMonitorProfile.metrics.controlPlane.enabled" -o tsv 2>/dev/null || echo "")"
  if [[ "$(echo "$cp_enabled" | tr "[:upper:]" "[:lower:]")" != "true" ]]; then
    print_error "Control plane metrics are NOT enabled on $CLUSTER_NAME (controlPlane.enabled='${cp_enabled:-<missing>}')."
    print_error "Re-run with ./deploy.sh --enable-with-cli, or run:"
    print_error "  az aks update -g $RESOURCE_GROUP -n $CLUSTER_NAME --enable-control-plane-metrics"
    exit 1
  fi
  print_message "Control plane metrics are enabled (controlPlane.enabled=true)."

  print_message "Managed Prometheus agent pods (kube-system):"
  kubectl get pods -n kube-system -l rsName=ama-metrics -o wide || true
  print_message "Control plane metrics are collected outside these pods, inside the AKS-managed control plane."
}

apply_configmap() {
  print_step "Applying ama-metrics-settings-configmap (control plane targets & keep lists)"
  kubectl apply -f "$K8S_DIR/ama-metrics-settings-configmap.yaml"
}

import_dashboards() {
  print_step "Importing Grafana dashboards"
  local id attempt
  for id in "${DASHBOARD_IDS[@]}"; do
    for attempt in $(seq 1 10); do
      if az grafana dashboard import \
        --name "$GRAFANA_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --definition "$id" \
        --overwrite true \
        --only-show-errors \
        --output none 2>/dev/null; then
        print_message "Imported dashboard $id"
        break
      fi
      if [[ $attempt -eq 10 ]]; then
        print_warning "Could not import dashboard $id. Import it manually from Grafana (Dashboards > New > Import > $id)."
      else
        print_warning "Dashboard $id import failed (RBAC may still be propagating). Retrying in 30s... ($attempt/10)"
        sleep 30
      fi
    done
  done
}

start_load_generator() {
  if [[ "$SKIP_LOAD" == "true" ]]; then
    print_message "Skipping load generator (--skip-load)."
    return
  fi
  print_step "Starting API server load generator"
  kubectl apply -f "$K8S_DIR/apiserver-load-generator.yaml"
  kubectl rollout status deployment/apiserver-load -n cp-metrics-demo --timeout=180s || true
}

show_summary() {
  print_step "Deployment complete"
  cat <<EOF

  Resource group : $RESOURCE_GROUP
  AKS cluster    : $CLUSTER_NAME
  Grafana        : $GRAFANA_ENDPOINT

  Next steps:
    1. Wait ~5-10 minutes for control plane metrics to show up.
    2. Open Grafana and browse to:
         - Dashboards > Kubernetes / API Server
         - Dashboards > Kubernetes / ETCD
    3. Try PromQL in Explore (Managed Prometheus data source), e.g.:
         sum by (verb) (rate(apiserver_request_total[5m]))
         histogram_quantile(0.99, sum by (le, verb) (rate(apiserver_request_duration_seconds_bucket[5m])))
         etcd_mvcc_db_total_size_in_bytes
    4. Stop the load:  kubectl delete -f k8s/apiserver-load-generator.yaml
    5. Clean up:       ./cleanup.sh

EOF
}

main() {
  parse_args "$@"
  check_prerequisites
  deploy_infrastructure
  get_credentials
  enable_control_plane_metrics_cli
  verify_control_plane_metrics
  apply_configmap
  import_dashboards
  start_load_generator
  show_summary
}

main "$@"
