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
  for cmd in az terraform kubectl helm envsubst ssh scp nc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "Required tool not found: $cmd"
      exit 1
    fi
  done

  if ! az account show >/dev/null 2>&1; then
    error "Azure CLI is not logged in. Run 'az login' first."
    exit 1
  fi

  if ! az extension show --name bastion >/dev/null 2>&1; then
    info "Installing the 'bastion' az CLI extension..."
    az extension add --name bastion --only-show-errors
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
  REDIS_PORT="$(terraform -chdir="$TF_DIR" output -raw redis_port)"
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
    POSTGRES_HOST POSTGRES_PASSWORD REDIS_HOST REDIS_PORT REDIS_PASSWORD HARBOR_OIDC_SETTINGS_JSON

  BASTION_NAME="$(terraform -chdir="$TF_DIR" output -raw bastion_name)"
  JUMPBOX_VM_ID="$(terraform -chdir="$TF_DIR" output -raw jumpbox_vm_id)"
  JUMPBOX_ADMIN_USERNAME="$(terraform -chdir="$TF_DIR" output -raw jumpbox_admin_username)"
  local_tunnel_port=2222

  # Password auth (the jumpbox default) is simpler to bootstrap; set JUMPBOX_SSH_KEY
  # to a private key path to use SSH key auth instead - it's the more secure option.
  if [[ -n "${JUMPBOX_SSH_KEY:-}" && -f "$JUMPBOX_SSH_KEY" ]]; then
    info "Using SSH key auth for the jumpbox (more secure than a password)."
    ssh_cmd=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$JUMPBOX_SSH_KEY" -p "$local_tunnel_port")
    scp_cmd=(scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$JUMPBOX_SSH_KEY" -P "$local_tunnel_port")
  else
    if ! command -v sshpass >/dev/null 2>&1; then
      error "sshpass is required for password-based jumpbox access (e.g. 'brew install hudochenkov/sshpass/sshpass')."
      error "Alternatively, set JUMPBOX_SSH_KEY to a private key path to use SSH key auth instead - it's also more secure."
      exit 1
    fi
    warn "Using password auth for the jumpbox. Set JUMPBOX_SSH_KEY for the more secure SSH key option instead."
    JUMPBOX_ADMIN_PASSWORD="$(terraform -chdir="$TF_DIR" output -raw jumpbox_admin_password)"
    ssh_cmd=(sshpass -p "$JUMPBOX_ADMIN_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$local_tunnel_port")
    scp_cmd=(sshpass -p "$JUMPBOX_ADMIN_PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$local_tunnel_port")
  fi

  info "Fetching kubeconfig for the private cluster (control-plane API call only, no VNet access needed)..."
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --file "$RENDERED_DIR/kubeconfig" --overwrite-existing

  info "Rendering Kubernetes manifests..."
  envsubst < "$MANIFESTS_DIR/cluster-issuer.yaml.tpl" > "$RENDERED_DIR/cluster-issuer.yaml"
  envsubst < "$MANIFESTS_DIR/secretproviderclass.yaml.tpl" > "$RENDERED_DIR/secretproviderclass.yaml"
  envsubst < "$MANIFESTS_DIR/harbor-values.yaml.tpl" > "$RENDERED_DIR/harbor-values.yaml"
  envsubst < "$MANIFESTS_DIR/harbor-certificate.yaml.tpl" > "$RENDERED_DIR/harbor-certificate.yaml"
  envsubst < "$MANIFESTS_DIR/harbor-ingress-route.yaml.tpl" > "$RENDERED_DIR/harbor-ingress-route.yaml"
  cp "$MANIFESTS_DIR/namespace.yaml" "$MANIFESTS_DIR/storageclass-azurefile-zrs-nfs.yaml" \
    "$MANIFESTS_DIR/keyvault-secret-sync.yaml" "$MANIFESTS_DIR/audit-log-forwarder.yaml" \
    "$MANIFESTS_DIR/remote-deploy.sh" "$RENDERED_DIR/"
  chmod +x "$RENDERED_DIR/remote-deploy.sh"

  info "Opening an Azure Bastion tunnel to the jumpbox (127.0.0.1:$local_tunnel_port)..."
  az network bastion tunnel \
    --name "$BASTION_NAME" --resource-group "$RESOURCE_GROUP" \
    --target-resource-id "$JUMPBOX_VM_ID" \
    --resource-port 22 --port "$local_tunnel_port" \
    --only-show-errors &>/tmp/harbor-bastion-tunnel.log &
  tunnel_pid=$!
  trap 'kill "$tunnel_pid" >/dev/null 2>&1 || true' EXIT

  info "Waiting for the tunnel to come up..."
  for _ in $(seq 1 30); do
    if nc -z 127.0.0.1 "$local_tunnel_port" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  info "Copying rendered manifests to the jumpbox..."
  "${ssh_cmd[@]}" "$JUMPBOX_ADMIN_USERNAME@127.0.0.1" 'mkdir -p /tmp/harbor-deploy'
  "${scp_cmd[@]}" "$RENDERED_DIR"/* "$JUMPBOX_ADMIN_USERNAME@127.0.0.1:/tmp/harbor-deploy/"

  info "Running the deployment on the jumpbox..."
  "${ssh_cmd[@]}" "$JUMPBOX_ADMIN_USERNAME@127.0.0.1" 'bash /tmp/harbor-deploy/remote-deploy.sh'
}

main "$@"
