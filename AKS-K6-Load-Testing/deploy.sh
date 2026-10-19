#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TRAEFIK_CHART_VERSION="42.0.0"
CERT_MANAGER_CHART_VERSION="v1.21.2"
# Grafana.com "Traefik Official Kubernetes Dashboard"
TRAEFIK_DASHBOARD_ID="17347"
TRAEFIK_DASHBOARD_UID="n5bu_kv4k"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() { printf "${GREEN}==>${NC} %s\n" "$1"; }
print_error() { printf "${RED}ERROR:${NC} %s\n" "$1" >&2; }
print_warning() { printf "${YELLOW}WARNING:${NC} %s\n" "$1"; }

check_prerequisites() {
  print_message "Checking prerequisites..."

  for tool in terraform az kubectl helm envsubst curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      print_error "$tool is not installed. Please install it first."
      exit 1
    fi
  done

  if ! az account show --output none; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
  fi

  TF_VAR_subscription_id="${TF_VAR_subscription_id:-$(az account show --query id -o tsv)}"
  export TF_VAR_subscription_id
  az account show --subscription "$TF_VAR_subscription_id" --output none

  if ! az extension show --name amg --output none 2>/dev/null; then
    print_error "Install the Grafana CLI extension first: az extension add --name amg"
    exit 1
  fi

  TF_VAR_grafana_admin_object_id="${TF_VAR_grafana_admin_object_id:-$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)}"
  export TF_VAR_grafana_admin_object_id
  if [[ -z "$TF_VAR_grafana_admin_object_id" ]]; then
    print_error "Cannot detect the Grafana administrator. Set TF_VAR_grafana_admin_object_id to the Azure CLI caller's Entra object ID."
    exit 1
  fi
  print_message "Prerequisites check passed!"
}

terraform_apply() {
  print_message "Provisioning infrastructure with Terraform..."
  print_warning "This may take 10-15 minutes. Terraform changes are automatically approved."

  terraform -chdir="$TF_DIR" init -input=false
  terraform -chdir="$TF_DIR" validate
  terraform -chdir="$TF_DIR" apply -auto-approve "$@"
}

get_credentials() {
  RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
  SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"
  HTTPBIN_FQDN="$(terraform -chdir="$TF_DIR" output -raw httpbin_fqdn)"
  INGRESS_PUBLIC_IP="$(terraform -chdir="$TF_DIR" output -raw ingress_public_ip)"
  INGRESS_PUBLIC_IP_NAME="$(terraform -chdir="$TF_DIR" output -raw ingress_public_ip_name)"
  DNS_ZONE_NAME="$(terraform -chdir="$TF_DIR" output -raw dns_zone_name)"
  DNS_ZONE_RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw dns_zone_resource_group)"
  CERT_MANAGER_CLIENT_ID="$(terraform -chdir="$TF_DIR" output -raw cert_manager_client_id)"
  ACME_EMAIL="$(terraform -chdir="$TF_DIR" output -raw acme_email)"
  GRAFANA_NAME="$(terraform -chdir="$TF_DIR" output -raw grafana_name)"
  GRAFANA_ENDPOINT="$(terraform -chdir="$TF_DIR" output -raw grafana_endpoint)"
  export RESOURCE_GROUP SUBSCRIPTION_ID HTTPBIN_FQDN INGRESS_PUBLIC_IP_NAME
  export DNS_ZONE_NAME DNS_ZONE_RESOURCE_GROUP CERT_MANAGER_CLIENT_ID ACME_EMAIL

  print_message "Fetching AKS credentials..."
  az aks get-credentials --subscription "$SUBSCRIPTION_ID" \
    --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --context "$CLUSTER_NAME" --overwrite-existing
}

deploy_sample_app() {
  print_message "Deploying httpbin..."
  kubectl --context "$CLUSTER_NAME" create namespace k6-demo --dry-run=client -o yaml | \
    kubectl --context "$CLUSTER_NAME" apply -f -
  kubectl --context "$CLUSTER_NAME" apply -f "$SCRIPT_DIR/k8s/target-app.yaml"
  kubectl --context "$CLUSTER_NAME" rollout status deployment/target-app -n k6-demo --timeout=300s
  kubectl --context "$CLUSTER_NAME" get service target-app -n k6-demo
}

configure_ingress() {
  print_message "Installing Traefik and cert-manager..."
  helm repo add traefik https://traefik.github.io/charts --force-update
  helm repo add jetstack https://charts.jetstack.io --force-update

  helm upgrade --install traefik traefik/traefik \
    --version "$TRAEFIK_CHART_VERSION" --kube-context "$CLUSTER_NAME" \
    --namespace traefik --create-namespace --wait --timeout 10m \
    -f <(envsubst "\${RESOURCE_GROUP} \${INGRESS_PUBLIC_IP_NAME}" < "$SCRIPT_DIR/k8s/traefik-values.yaml.tpl")

  helm upgrade --install cert-manager jetstack/cert-manager \
    --version "$CERT_MANAGER_CHART_VERSION" --kube-context "$CLUSTER_NAME" \
    --namespace cert-manager --create-namespace --wait --timeout 5m \
    --set crds.enabled=true \
    --set-string "serviceAccount.annotations.azure\.workload\.identity/client-id=$CERT_MANAGER_CLIENT_ID" \
    --set-string 'podLabels.azure\.workload\.identity/use=true'

  kubectl --context "$CLUSTER_NAME" rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s
  envsubst "\${SUBSCRIPTION_ID} \${DNS_ZONE_RESOURCE_GROUP} \${DNS_ZONE_NAME} \${CERT_MANAGER_CLIENT_ID} \${ACME_EMAIL} \${HTTPBIN_FQDN}" \
    < "$SCRIPT_DIR/k8s/httpbin-ingress.yaml.tpl" | kubectl --context "$CLUSTER_NAME" apply -f -
  print_message "Waiting for the Let's Encrypt certificate (DNS propagation can take several minutes)..."
  kubectl --context "$CLUSTER_NAME" wait --for=condition=Ready certificate/httpbin-tls -n k6-demo --timeout=900s
  curl --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 2 --max-time 15 \
    --resolve "$HTTPBIN_FQDN:443:$INGRESS_PUBLIC_IP" "https://$HTTPBIN_FQDN/status/200"
}

configure_monitoring() {
  print_message "Applying Azure Monitor settings and the Azure-specific Traefik ServiceMonitor..."
  kubectl --context "$CLUSTER_NAME" apply -f "$SCRIPT_DIR/monitoring/ama-metrics-settings-configmap-v2.yaml"
  kubectl --context "$CLUSTER_NAME" wait --for=condition=Established \
    crd/servicemonitors.azmonitoring.coreos.com --timeout=180s
  kubectl --context "$CLUSTER_NAME" apply -f "$SCRIPT_DIR/monitoring/traefik-azure-monitor-servicemonitor.yaml"
  kubectl --context "$CLUSTER_NAME" rollout status deployment/ama-metrics -n kube-system --timeout=300s

  print_message "Importing the official Traefik dashboard ($TRAEFIK_DASHBOARD_ID) from Grafana.com..."
  # Data source input maps to the Prometheus source Managed Grafana creates for the linked workspace.
  if ! az grafana dashboard import --subscription "$SUBSCRIPTION_ID" \
    --resource-group "$RESOURCE_GROUP" --name "$GRAFANA_NAME" \
    --definition "$TRAEFIK_DASHBOARD_ID" --overwrite true --output none; then
    print_error "Dashboard import failed. Confirm Grafana Admin for the CLI caller; if RBAC is still propagating, rerun deploy.sh."
    return 1
  fi
}

show_summary() {
  printf '\n'
  print_message "Deployment complete!"
  printf '\n  Resource group : %s\n  AKS cluster    : %s\n\n' "$RESOURCE_GROUP" "$CLUSTER_NAME"
  printf '  httpbin        : https://%s\n' "$HTTPBIN_FQDN"
  printf '  Grafana        : %s/d/%s\n\n' "${GRAFANA_ENDPOINT%/}" "$TRAEFIK_DASHBOARD_UID"
  printf 'Run: BASE_URL=https://%s TEST_TYPE=smoke k6 run %s/k6/load-test.js\n' "$HTTPBIN_FQDN" "$SCRIPT_DIR"
  print_warning "Allow a few minutes for metrics to appear. In-cluster tests must use the HTTPS hostname to generate Traefik traffic."
}

check_prerequisites
terraform_apply "$@"
get_credentials
deploy_sample_app
configure_ingress
configure_monitoring
show_summary