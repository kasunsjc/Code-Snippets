#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
MANIFESTS_DIR="$SCRIPT_DIR/kubernetes-manifests"
RENDERED_DIR="$SCRIPT_DIR/.rendered"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

json_escape() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//\"/\\\"}"
  input="${input//$'\n'/\\n}"
  input="${input//$'\r'/\\r}"
  input="${input//$'\t'/\\t}"
  printf '%s' "$input"
}

check_prerequisites() {
  for cmd in az terraform kubectl helm envsubst; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "Required tool not found: $cmd"
      exit 1
    fi
  done

  if ! az account show >/dev/null 2>&1; then
    error "Azure CLI is not logged in. Run 'az login' first."
    exit 1
  fi
}

main() {
  check_prerequisites
  mkdir -p "$RENDERED_DIR"

  info "Initializing Terraform..."
  terraform -chdir="$TF_DIR" init -input=false

  info "Applying Terraform configuration..."
  terraform -chdir="$TF_DIR" apply -auto-approve

  info "Fetching AKS credentials..."
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
  RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
  SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"
  TENANT_ID="$(terraform -chdir="$TF_DIR" output -raw tenant_id)"
  DNS_ZONE_NAME="$(terraform -chdir="$TF_DIR" output -raw dns_zone_name)"
  DNS_ZONE_RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw dns_zone_resource_group)"
  HARBOR_FQDN="$(terraform -chdir="$TF_DIR" output -raw harbor_fqdn)"
  ACME_EMAIL="$(terraform -chdir="$TF_DIR" output -raw acme_email)"
  CERT_MANAGER_CLIENT_ID="$(terraform -chdir="$TF_DIR" output -raw cert_manager_client_id)"
  KEY_VAULT_NAME="$(terraform -chdir="$TF_DIR" output -raw key_vault_name)"
  KV_CSI_CLIENT_ID="$(terraform -chdir="$TF_DIR" output -raw kv_csi_client_id)"
  HARBOR_ADMIN_PASSWORD="$(terraform -chdir="$TF_DIR" output -raw harbor_admin_password)"
  POSTGRES_HOST="$(terraform -chdir="$TF_DIR" output -raw postgres_host)"
  POSTGRES_PASSWORD="$(terraform -chdir="$TF_DIR" output -raw postgres_password)"
  REDIS_HOST="$(terraform -chdir="$TF_DIR" output -raw redis_host)"
  REDIS_PASSWORD="$(terraform -chdir="$TF_DIR" output -raw redis_password)"
  ENABLE_OIDC_AUTH="$(terraform -chdir="$TF_DIR" output -raw enable_oidc_auth)"

  HARBOR_OIDC_SETTINGS_JSON='"auth_mode": "db_auth",'
  if [[ "$ENABLE_OIDC_AUTH" == "true" ]]; then
    HARBOR_OIDC_ENDPOINT="$(terraform -chdir="$TF_DIR" output -raw harbor_oidc_endpoint)"
    HARBOR_OIDC_CLIENT_ID="$(terraform -chdir="$TF_DIR" output -raw harbor_oidc_client_id)"
    HARBOR_OIDC_CLIENT_SECRET="$(terraform -chdir="$TF_DIR" output -raw harbor_oidc_client_secret)"
    HARBOR_ADMIN_GROUP_OBJECT_ID="$(terraform -chdir="$TF_DIR" output -raw harbor_admin_group_object_id)"
    HARBOR_OIDC_SETTINGS_JSON="\"auth_mode\": \"oidc_auth\",\
\"oidc_name\": \"entra-id\",\
\"oidc_endpoint\": \"$(json_escape "$HARBOR_OIDC_ENDPOINT")\",\
\"oidc_client_id\": \"$(json_escape "$HARBOR_OIDC_CLIENT_ID")\",\
\"oidc_client_secret\": \"$(json_escape "$HARBOR_OIDC_CLIENT_SECRET")\",\
\"oidc_scope\": \"openid,profile,email,offline_access\",\
\"oidc_verify_cert\": true,\
\"oidc_auto_onboard\": true,\
\"oidc_user_claim\": \"preferred_username\",\
\"oidc_groups_claim\": \"groups\",\
\"oidc_admin_group\": \"$(json_escape "$HARBOR_ADMIN_GROUP_OBJECT_ID")\","
  fi

  export SUBSCRIPTION_ID TENANT_ID DNS_ZONE_NAME DNS_ZONE_RESOURCE_GROUP HARBOR_FQDN \
    ACME_EMAIL CERT_MANAGER_CLIENT_ID KEY_VAULT_NAME KV_CSI_CLIENT_ID HARBOR_ADMIN_PASSWORD \
    POSTGRES_HOST POSTGRES_PASSWORD REDIS_HOST REDIS_PASSWORD HARBOR_OIDC_SETTINGS_JSON

  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

  info "Installing Helm repositories..."
  helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
  helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
  helm repo add harbor https://helm.goharbor.io --force-update >/dev/null
  helm repo update >/dev/null

  info "Installing Traefik..."
  helm upgrade --install traefik traefik/traefik \
    --namespace traefik --create-namespace \
    --version "41.5.0" \
    --wait --timeout 5m

  info "Installing cert-manager..."
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version "1.21.2" \
    --set crds.enabled=true \
    --wait --timeout 5m

  info "Creating Harbor namespace and base manifests..."
  kubectl apply -f "$MANIFESTS_DIR/namespace.yaml"
  envsubst < "$MANIFESTS_DIR/cluster-issuer.yaml.tpl" > "$RENDERED_DIR/cluster-issuer.yaml"
  kubectl apply -f "$RENDERED_DIR/cluster-issuer.yaml"

  info "Applying storage class and secret sync resources..."
  kubectl apply -f "$MANIFESTS_DIR/storageclass-azurefile-zrs-nfs.yaml"
  envsubst < "$MANIFESTS_DIR/secretproviderclass.yaml.tpl" > "$RENDERED_DIR/secretproviderclass.yaml"
  kubectl apply -f "$RENDERED_DIR/secretproviderclass.yaml"
  kubectl apply -f "$MANIFESTS_DIR/keyvault-secret-sync.yaml"

  info "Applying Harbor audit-log forwarder (must be Ready before Harbor installs)..."
  kubectl apply -f "$MANIFESTS_DIR/audit-log-forwarder.yaml"
  kubectl rollout status deployment/harbor-audit-forwarder -n harbor --timeout=120s

  info "Applying Harbor values template..."
  envsubst < "$MANIFESTS_DIR/harbor-values.yaml.tpl" > "$RENDERED_DIR/harbor-values.yaml"

  info "Deploying Harbor..."
  helm upgrade --install harbor harbor/harbor \
    --namespace harbor \
    --create-namespace \
    -f "$RENDERED_DIR/harbor-values.yaml" \
    --version "1.19.2" \
    --wait --timeout 10m

  info "Applying Harbor ingress and certificate manifests..."
  envsubst < "$MANIFESTS_DIR/harbor-certificate.yaml.tpl" > "$RENDERED_DIR/harbor-certificate.yaml"
  envsubst < "$MANIFESTS_DIR/harbor-ingress-route.yaml.tpl" > "$RENDERED_DIR/harbor-ingress-route.yaml"
  kubectl apply -f "$RENDERED_DIR/harbor-certificate.yaml"
  kubectl apply -f "$RENDERED_DIR/harbor-ingress-route.yaml"

  info "Harbor deployment completed with Entra ID OIDC configuration."
}

main "$@"
