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

# --- Step 5: Apply ingress manifest ----------------------------------------

info "Applying Argo CD ingress manifest..."
sed \
  -e "s#https://<key-vault-name>.vault.azure.net/certificates/argocd-ingress-tls#${KEY_VAULT_CERT_URI}#g" \
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
