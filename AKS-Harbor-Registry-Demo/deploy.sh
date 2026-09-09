#!/bin/bash
# Provisions Azure infra with Terraform, then installs Traefik, cert-manager,
# the Harbor audit-log forwarder, Harbor, and the Azure Prometheus ServiceMonitor.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
MANIFESTS_DIR="$SCRIPT_DIR/kubernetes-manifests"
MONITORING_DIR="$SCRIPT_DIR/azure-config/monitoring"
RENDERED_DIR="$SCRIPT_DIR/.rendered"

HARBOR_CHART_VERSION="1.19.2"
TRAEFIK_CHART_VERSION="34.4.1"
CERT_MANAGER_CHART_VERSION="1.16.2"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
  info "Checking prerequisites..."
  local missing=0
  for cmd in az terraform kubectl helm envsubst; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required tool not found: $cmd"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 1

  if ! az account show &>/dev/null; then
    error "Not logged in to Azure. Run 'az login' first."
    exit 1
  fi
}

wait_for_lb_ip() {
  local namespace="$1" svc_name="$2"
  local ip=""
  info "Waiting for LoadBalancer external IP on $namespace/$svc_name..." >&2
  for _ in $(seq 1 60); do
    ip="$(kubectl get svc "$svc_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
    sleep 5
  done
  error "Timed out waiting for $namespace/$svc_name external IP."
  exit 1
}

main() {
  check_prerequisites
  mkdir -p "$RENDERED_DIR"

  # --- 1. Terraform: Azure infra -----------------------------------------
  info "Running terraform init/apply..."
  terraform -chdir="$TF_DIR" init -input=false
  terraform -chdir="$TF_DIR" apply -auto-approve

  RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
  CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
  SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"
  DNS_ZONE_NAME="$(terraform -chdir="$TF_DIR" output -raw dns_zone_name)"
  DNS_ZONE_RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw dns_zone_resource_group)"
  HARBOR_FQDN="$(terraform -chdir="$TF_DIR" output -raw harbor_fqdn)"
  HARBOR_SUBDOMAIN="$(terraform -chdir="$TF_DIR" output -raw harbor_subdomain)"
  CERT_MANAGER_CLIENT_ID="$(terraform -chdir="$TF_DIR" output -raw cert_manager_client_id)"
  ACME_EMAIL="$(terraform -chdir="$TF_DIR" output -raw acme_email)"
  HARBOR_ADMIN_PASSWORD="$(terraform -chdir="$TF_DIR" output -raw harbor_admin_password)"
  LOG_ANALYTICS_WORKSPACE_NAME="$(terraform -chdir="$TF_DIR" output -raw log_analytics_workspace_name)"
  GRAFANA_ENDPOINT="$(terraform -chdir="$TF_DIR" output -raw grafana_endpoint)"
  ENABLE_OIDC_AUTH="$(terraform -chdir="$TF_DIR" output -raw enable_oidc_auth)"

  HARBOR_OIDC_SETTINGS_JSON=""
  HARBOR_ADMIN_GROUP_OBJECT_ID=""
  HARBOR_OIDC_CLIENT_ID=""
  if [[ "$ENABLE_OIDC_AUTH" == "true" ]]; then
    HARBOR_OIDC_CLIENT_ID="$(terraform -chdir="$TF_DIR" output -raw harbor_oidc_client_id)"
    HARBOR_OIDC_CLIENT_SECRET="$(terraform -chdir="$TF_DIR" output -raw harbor_oidc_client_secret)"
    HARBOR_OIDC_TENANT_ID="$(terraform -chdir="$TF_DIR" output -raw harbor_oidc_tenant_id)"
    HARBOR_OIDC_ENDPOINT="$(terraform -chdir="$TF_DIR" output -raw harbor_oidc_endpoint)"
    HARBOR_ADMIN_GROUP_OBJECT_ID="$(terraform -chdir="$TF_DIR" output -raw harbor_admin_group_object_id)"
    HARBOR_OIDC_SETTINGS_JSON=",\"auth_mode\": \"oidc_auth\",\"oidc_name\": \"entra-id\",\"oidc_endpoint\": \"${HARBOR_OIDC_ENDPOINT}\",\"oidc_client_id\": \"${HARBOR_OIDC_CLIENT_ID}\",\"oidc_client_secret\": \"${HARBOR_OIDC_CLIENT_SECRET}\",\"oidc_scope\": \"openid,profile,email,offline_access\",\"oidc_verify_cert\": true,\"oidc_auto_onboard\": true,\"oidc_user_claim\": \"preferred_username\",\"oidc_groups_claim\": \"groups\",\"oidc_admin_group\": \"${HARBOR_ADMIN_GROUP_OBJECT_ID}\""
  fi

  export SUBSCRIPTION_ID DNS_ZONE_NAME DNS_ZONE_RESOURCE_GROUP HARBOR_FQDN CERT_MANAGER_CLIENT_ID ACME_EMAIL HARBOR_OIDC_SETTINGS_JSON

  info "Fetching AKS credentials..."
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

  # --- 2. Azure Monitor agent configuration -------------------------------
  # Keep Harbor stdout audit logs in ContainerLogV2 and configure AMA metrics.
  info "Applying Azure Monitor Container Insights and metrics settings..."
  kubectl apply -f "$MONITORING_DIR/container-azm-ms-agentconfig.yaml"
  kubectl apply -f "$MONITORING_DIR/ama-metrics-settings-configmap-v2.yaml"

  # --- 3. Helm repos -------------------------------------------------------
  helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
  helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
  helm repo add harbor https://helm.goharbor.io --force-update >/dev/null
  helm repo update >/dev/null

  # --- 4. Traefik ingress controller --------------------------------------
  info "Installing Traefik..."
  helm upgrade --install traefik traefik/traefik \
    --version "$TRAEFIK_CHART_VERSION" \
    --namespace traefik --create-namespace \
    --wait --timeout 5m

  TRAEFIK_LB_IP="$(wait_for_lb_ip traefik traefik)"
  info "Traefik LoadBalancer IP: $TRAEFIK_LB_IP"

  # --- 5. cert-manager (workload identity, no client secret) --------------
  info "Installing cert-manager..."
  helm upgrade --install cert-manager jetstack/cert-manager \
    --version "$CERT_MANAGER_CHART_VERSION" \
    --namespace cert-manager --create-namespace \
    --set crds.enabled=true \
    --set "serviceAccount.annotations.azure\.workload\.identity/client-id=$CERT_MANAGER_CLIENT_ID" \
    --set-string "podLabels.azure\.workload\.identity/use=true" \
    --wait --timeout 5m

  kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=120s

  info "Applying Let's Encrypt ClusterIssuer (Azure DNS DNS-01)..."
  envsubst < "$MANIFESTS_DIR/cluster-issuer.yaml.tpl" > "$RENDERED_DIR/cluster-issuer.yaml"
  kubectl apply -f "$RENDERED_DIR/cluster-issuer.yaml"

  # --- 6. Harbor audit-log forwarder (must be Ready before Harbor) --------
  info "Deploying harbor namespace and audit-log forwarder..."
  kubectl apply -f "$MANIFESTS_DIR/namespace.yaml"
  kubectl apply -f "$MANIFESTS_DIR/audit-log-forwarder.yaml"
  kubectl -n harbor rollout status deployment/harbor-audit-forwarder --timeout=180s

  # --- 7. Harbor ------------------------------------------------------------
  info "Installing Harbor..."
  envsubst < "$MANIFESTS_DIR/harbor-values.yaml.tpl" > "$RENDERED_DIR/harbor-values.yaml"
  # Contains the OIDC client secret (embedded in configureUserSettings JSON) when SSO is enabled.
  chmod 600 "$RENDERED_DIR/harbor-values.yaml"
  # Single-quoted YAML scalar so special characters from random_password (":", "#", etc.) don't break parsing.
  HARBOR_ADMIN_PASSWORD_YAML="${HARBOR_ADMIN_PASSWORD//\'/\'\'}"
  cat > "$RENDERED_DIR/harbor-secret-values.yaml" <<EOF
harborAdminPassword: '${HARBOR_ADMIN_PASSWORD_YAML}'
EOF
  chmod 600 "$RENDERED_DIR/harbor-secret-values.yaml"
  rm -rf "$RENDERED_DIR/harbor"
  helm pull harbor/harbor \
    --version "$HARBOR_CHART_VERSION" \
    --untar \
    --untardir "$RENDERED_DIR"
  info "Validating Harbor Helm values..."
  helm lint "$RENDERED_DIR/harbor" \
    --namespace harbor \
    -f "$RENDERED_DIR/harbor-values.yaml" \
    -f "$RENDERED_DIR/harbor-secret-values.yaml"
  helm upgrade --install harbor harbor/harbor \
    --version "$HARBOR_CHART_VERSION" \
    --namespace harbor \
    -f "$RENDERED_DIR/harbor-values.yaml" \
    -f "$RENDERED_DIR/harbor-secret-values.yaml" \
    --wait --timeout 10m

  info "Applying Harbor TLS Certificate and Traefik routes..."
  envsubst < "$MANIFESTS_DIR/harbor-certificate.yaml.tpl" > "$RENDERED_DIR/harbor-certificate.yaml"
  envsubst < "$MANIFESTS_DIR/harbor-ingress-route.yaml.tpl" > "$RENDERED_DIR/harbor-ingress-route.yaml"
  kubectl apply -f "$RENDERED_DIR/harbor-certificate.yaml"
  kubectl apply -f "$RENDERED_DIR/harbor-ingress-route.yaml"

  info "Applying Azure Monitor ServiceMonitor for Harbor metrics..."
  kubectl apply -f "$MANIFESTS_DIR/harbor-azure-monitor-servicemonitor.yaml"

  # --- 8. Azure DNS record --------------------------------------------------
  info "Upserting Azure DNS A record for $HARBOR_FQDN -> $TRAEFIK_LB_IP..."
  az network dns record-set a create \
    --resource-group "$DNS_ZONE_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE_NAME" \
    --name "$HARBOR_SUBDOMAIN" \
    --ttl 60 &>/dev/null || true
  # Remove any stale IPs (e.g. from a previous deploy) before adding the current one.
  EXISTING_IPS="$(az network dns record-set a show \
    --resource-group "$DNS_ZONE_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE_NAME" \
    --name "$HARBOR_SUBDOMAIN" \
    --query "aRecords[].ipv4Address" -o tsv 2>/dev/null || true)"
  for ip in $EXISTING_IPS; do
    if [[ "$ip" != "$TRAEFIK_LB_IP" ]]; then
      az network dns record-set a remove-record \
        --resource-group "$DNS_ZONE_RESOURCE_GROUP" \
        --zone-name "$DNS_ZONE_NAME" \
        --record-set-name "$HARBOR_SUBDOMAIN" \
        --ipv4-address "$ip" >/dev/null
    fi
  done
  az network dns record-set a add-record \
    --resource-group "$DNS_ZONE_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE_NAME" \
    --record-set-name "$HARBOR_SUBDOMAIN" \
    --ipv4-address "$TRAEFIK_LB_IP" >/dev/null

  # --- Summary ---------------------------------------------------------------
  cat <<EOF

${GREEN}Harbor demo deployed.${NC}

  Harbor URL:        https://${HARBOR_FQDN}
  Harbor admin user: admin
  Harbor admin pass: not printed here - retrieve with:
    terraform -chdir=${TF_DIR} output -raw harbor_admin_password
  Grafana:            https://${GRAFANA_ENDPOINT}
  Log Analytics:      ${LOG_ANALYTICS_WORKSPACE_NAME}

  DNS propagation and Let's Encrypt certificate issuance can take a few
  minutes. If https://${HARBOR_FQDN} shows a TLS error, wait and retry:
    kubectl get certificate -n harbor
    kubectl describe certificate harbor-tls -n harbor

  Verify audit log forwarding (after logging into Harbor once):
    kubectl logs deployment/harbor-audit-forwarder -n harbor --tail=20

  Verify Prometheus metrics:
    kubectl get servicemonitor.azmonitoring.coreos.com -n harbor
EOF

  if [[ "$ENABLE_OIDC_AUTH" == "true" ]]; then
    cat <<EOF

${GREEN}OIDC SSO enabled.${NC}

  Entra app (client ID):    ${HARBOR_OIDC_CLIENT_ID}
  harbor-admins group ID:   ${HARBOR_ADMIN_GROUP_OBJECT_ID}

  Maintainer/Developer/Guest/Limited Guest/ProjectAdmin groups were created
  but are NOT auto-assigned to any project (Harbor has no global mapping for
  those roles). For each project: Harbor UI -> Project -> Members -> + User
  Group -> paste the group's object ID from:
    terraform -chdir=${TF_DIR} output harbor_projectadmin_group_object_id
    terraform -chdir=${TF_DIR} output harbor_maintainer_group_object_id
    terraform -chdir=${TF_DIR} output harbor_developer_group_object_id
    terraform -chdir=${TF_DIR} output harbor_guest_group_object_id
    terraform -chdir=${TF_DIR} output harbor_limited_guest_group_object_id
EOF
  fi
}

main "$@"
