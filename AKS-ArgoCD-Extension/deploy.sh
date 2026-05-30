#!/bin/bash
# Unified deployment script for the AKS Argo CD extension demo.
#
# This script:
#   1. Runs `terraform init` and `terraform apply` to provision all Azure
#      infrastructure (AKS, Key Vault, Entra ID app + group, Argo CD extension).
#   2. Fetches kubeconfig, waits for the extension to become ready.
#   3. Applies post-deploy K8s manifests (ingress, sample app).
#   4. Prints connection info (NGINX IP, admin password).
#
# Prerequisites:
#   - Azure CLI logged in (`az login`)
#   - Terraform >= 1.6 installed
#   - kubectl installed
#   - A terraform.tfvars file in ./terraform with required variables:
#       dns_zone_name, dns_zone_resource_group, argocd_hostname, certificate_pfx_path
#
# Usage:
#   cd AKS-ArgoCD-Extension
#   ./deploy.sh              # full deploy (init + apply + configure)
#   ./deploy.sh --destroy    # tear everything down

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
K8S_DIR="${SCRIPT_DIR}/k8s"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

info()  { echo -e "\n\033[1;34m▶ $*\033[0m"; }
ok()    { echo -e "\033[1;32m✔ $*\033[0m"; }
err()   { echo -e "\033[1;31m✖ $*\033[0m" >&2; }

check_prerequisites() {
  local missing=()
  command -v az        >/dev/null || missing+=(az)
  command -v terraform >/dev/null || missing+=(terraform)
  command -v kubectl   >/dev/null || missing+=(kubectl)
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Destroy path
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--destroy" ]]; then
  info "Destroying all resources..."
  cd "${TF_DIR}"
  terraform destroy -auto-approve
  ok "All resources destroyed."
  exit 0
fi

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------

check_prerequisites

# --- Step 1: Terraform init & apply ----------------------------------------

info "Initializing Terraform..."
cd "${TF_DIR}"
terraform init -input=false

info "Applying Terraform configuration..."
terraform apply -auto-approve

ok "Terraform apply complete."

# --- Step 2: Read Terraform outputs ----------------------------------------
# NOTE: The time_sleep resource inside Terraform already waits 90 s for RBAC
# propagation. After kubeconfig is fetched we do one extra restart of
# external-dns so it picks up the fresh role assignments cleanly.

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
KEY_VAULT_CERT_URI=$(terraform output -raw key_vault_certificate_uri)
ARGOCD_HOST=$(terraform output -raw argocd_hostname)
ADMIN_GROUP_ID=$(terraform output -raw argocd_admin_group_object_id)

# --- Step 3: Get kubeconfig -----------------------------------------------

info "Fetching kubeconfig for cluster '${CLUSTER_NAME}'..."
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --overwrite-existing

# --- Step 4: Wait for Argo CD extension ------------------------------------

info "Waiting for the Argo CD extension to finish provisioning..."
az k8s-extension show \
  --cluster-type managedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name argocd \
  --query "provisioningState" -o tsv

info "Waiting for argocd-server rollout..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=10m

ok "Argo CD extension is ready."

# --- Step 4b: Restart external-dns to pick up fresh RBAC ------------------
# The App Routing managed identity is recreated with each new cluster.
# Restart external-dns so it acquires a fresh token after the role
# assignments have propagated (time_sleep in Terraform already waited 90 s).
info "Restarting external-dns to apply new role assignments..."
kubectl -n app-routing-system rollout restart deployment external-dns
kubectl -n app-routing-system rollout status deployment external-dns --timeout=3m
ok "external-dns is running."

# --- Step 5: Configure NginxIngressController with KV default SSL cert -----
#
# WHY THIS IS NEEDED:
#   The AKS App Routing addon manages an nginx ingress controller. By default
#   it serves a self-signed certificate, causing ERR_CERT_AUTHORITY_INVALID.
#
# WHAT THIS DOES (mirrors the Azure Portal flow):
#   1. Patches the NginxIngressController CR with the Key Vault certificate URI.
#   2. The App Routing operator sees the change and creates a SecretProviderClass
#      in app-routing-system namespace.
#   3. The Secrets Store CSI driver (enabled via key_vault_secrets_provider in
#      Terraform) mounts the cert from Key Vault and writes it as a
#      kubernetes.io/tls Secret (keyvault-nginx-default).
#   4. The operator restarts nginx with:
#        --default-ssl-certificate=app-routing-system/keyvault-nginx-default
#   5. Every ingress using ingressClassName: webapprouting.kubernetes.azure.com
#      is now served with the real certificate — no per-ingress annotation needed.
#
# NOTE: The NginxIngressController CR is created automatically by the App Routing
# addon when the cluster first becomes ready. We wait for it before patching.

info "Waiting for NginxIngressController CR to be available..."
kubectl wait nginxingresscontroller default \
  --for=condition=Available \
  --timeout=5m

info "Configuring NginxIngressController default SSL certificate from Key Vault..."
# This is the Terraform/CLI equivalent of:
#   Portal → AKS → App Routing → HTTPS → select Key Vault + certificate
kubectl patch nginxingresscontroller default \
  --type=merge \
  -p "{\"spec\":{\"defaultSSLCertificate\":{\"keyVaultURI\":\"${KEY_VAULT_CERT_URI}\"}}}"

info "Waiting for App Routing operator to sync the certificate from Key Vault..."
# The operator creates the TLS secret asynchronously. We poll until it exists
# so the nginx rollout that follows uses the real cert immediately.
for i in $(seq 1 30); do
  if kubectl -n app-routing-system get secret keyvault-nginx-default >/dev/null 2>&1; then
    ok "Certificate synced (keyvault-nginx-default secret exists)."
    break
  fi
  [[ $i -eq 30 ]] && { err "Timed out waiting for cert sync."; exit 1; }
  sleep 5
done

info "Applying Argo CD ingress manifest..."
sed \
  -e "s#argocd.example.com#${ARGOCD_HOST}#g" \
  "${K8S_DIR}/argocd-ingress.yaml" | kubectl apply -f -

# --- Step 6: Print NGINX public IP for DNS --------------------------------

info "Retrieving App Routing NGINX public IP..."
NGINX_IP=$(kubectl -n app-routing-system get svc nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo ""
echo "  App Routing NGINX public IP: ${NGINX_IP}"
echo "  Create an A record: ${ARGOCD_HOST%%.*} -> ${NGINX_IP} in your DNS zone."
echo ""

# --- Step 7: Apply sample application -------------------------------------

info "Applying sample Argo CD Application..."
kubectl apply -f "${K8S_DIR}/sample-application.yaml"

# --- Step 8: Print admin password ------------------------------------------

info "Argo CD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo ""

# --- Summary ---------------------------------------------------------------

echo ""
ok "Deployment complete!"
echo ""
echo "  URL:   https://${ARGOCD_HOST}/"
echo "  SSO:   Log in via Microsoft Entra ID (members of argocd-admins group get admin role)"
echo "  Group: ${ADMIN_GROUP_ID}"
echo ""
