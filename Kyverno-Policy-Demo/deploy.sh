#!/usr/bin/env bash
# =============================================================================
# deploy.sh - Kyverno Policy Demo - Full Deployment
# =============================================================================
# This script:
#   1. Initialises and applies Terraform to provision AKS + Log Analytics
#   2. Configures kubectl with AKS credentials
#   3. Installs Kyverno via Helm
#   4. Creates the demo namespace
#
# Prerequisites:
#   - Azure CLI (az) — authenticated with 'az login'
#   - Terraform >= 1.6.0
#   - kubectl
#   - helm >= 3.14
# =============================================================================
set -e

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

# Kyverno Helm chart settings
KYVERNO_CHART_VERSION="${KYVERNO_CHART_VERSION:-3.2.6}"
KYVERNO_NAMESPACE="kyverno"

# ── Helpers ──────────────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${NC}"
}

print_step() {
  echo -e "\n${CYAN}▶ $1${NC}"
}

check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${RED}✘ Required tool not found: $1${NC}"
    echo -e "  Please install $1 and re-run this script."
    exit 1
  fi
  echo -e "  ${GREEN}✔${NC} $1 found ($(command -v "$1"))"
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
print_header "Kyverno Policy Demo — Deployment"

print_step "Checking required tools..."
check_dependency az
check_dependency terraform
check_dependency kubectl
check_dependency helm

print_step "Verifying Azure CLI login..."
SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
if [[ -z "$SUBSCRIPTION" ]]; then
  echo -e "${RED}✘ Not logged in to Azure CLI. Run 'az login' first.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✔${NC} Logged in. Active subscription: ${BOLD}$SUBSCRIPTION${NC}"

# ── Step 1: Terraform ─────────────────────────────────────────────────────────
print_header "Step 1: Provisioning Infrastructure with Terraform"

cd "$TF_DIR"

if [[ ! -f "terraform.tfvars" ]]; then
  echo -e "${YELLOW}  ⚠ terraform.tfvars not found.${NC}"
  echo -e "  Copying terraform.tfvars.example → terraform.tfvars"
  cp terraform.tfvars.example terraform.tfvars
  echo -e "${YELLOW}  Edit terraform/terraform.tfvars with your values and re-run this script.${NC}"
  exit 1
fi

print_step "Running terraform init..."
terraform init -upgrade

print_step "Running terraform plan..."
terraform plan -out=tfplan

print_step "Running terraform apply..."
terraform apply tfplan
rm -f tfplan

# ── Step 2: Configure kubectl ──────────────────────────────────────────────────
print_header "Step 2: Configuring kubectl"

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)

print_step "Getting AKS credentials for cluster '$CLUSTER_NAME'..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

print_step "Verifying cluster connectivity..."
kubectl cluster-info
echo -e "  ${GREEN}✔${NC} kubectl is connected to '$CLUSTER_NAME'."

# ── Step 3: Install Kyverno ───────────────────────────────────────────────────
print_header "Step 3: Installing Kyverno via Helm"

print_step "Adding Kyverno Helm repository..."
helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm repo update

print_step "Installing Kyverno chart v${KYVERNO_CHART_VERSION}..."
helm upgrade --install kyverno kyverno/kyverno \
  --namespace "$KYVERNO_NAMESPACE" \
  --create-namespace \
  --version "$KYVERNO_CHART_VERSION" \
  --set admissionController.replicas=3 \
  --set backgroundController.replicas=2 \
  --set cleanupController.replicas=2 \
  --set reportsController.replicas=2 \
  --wait \
  --timeout 10m

print_step "Waiting for Kyverno admission controller to be ready..."
kubectl rollout status deployment/kyverno-admission-controller \
  -n "$KYVERNO_NAMESPACE" --timeout=120s

echo -e "  ${GREEN}✔${NC} Kyverno is running."
kubectl get pods -n "$KYVERNO_NAMESPACE"

# ── Step 4: Create Demo Namespace ──────────────────────────────────────────────
print_header "Step 4: Creating Demo Namespace"

print_step "Creating 'demo' namespace..."
kubectl get namespace demo &>/dev/null || kubectl create namespace demo
echo -e "  ${GREEN}✔${NC} Namespace 'demo' is ready."

# ── Complete ──────────────────────────────────────────────────────────────────
print_header "Deployment Complete!"

echo ""
echo -e "  ${GREEN}${BOLD}Kyverno Policy Demo is ready!${NC}"
echo ""
echo -e "  Cluster   : ${BOLD}$CLUSTER_NAME${NC}"
echo -e "  Namespace : ${BOLD}$KYVERNO_NAMESPACE${NC}"
echo ""
echo -e "  ${CYAN}Next step — deploy policies manually:${NC}"
echo -e "  ${BOLD}See POLICY-GUIDE.md${NC}"
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "  kubectl get clusterpolicies"
echo -e "  kubectl get policyreport -A"
echo -e "  kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno-admission-controller --tail=50"
echo ""
