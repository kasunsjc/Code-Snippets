#!/usr/bin/env bash
# =============================================================================
# cleanup.sh - Kyverno Policy Demo - Full Teardown
# =============================================================================
# This script removes all resources created by deploy.sh:
#   1. Removes demo namespace and test resources
#   2. Removes Kyverno policies (best-effort)
#   3. Destroys all Azure resources with Terraform
#   4. Cleans local kubeconfig entries
#
# WARNING: This is a destructive operation. All data will be lost.
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

# Resolve expected AKS context name from Terraform output when available.
DEFAULT_AKS_CONTEXT="aks-kyverno-demo"
AKS_CONTEXT_NAME="$DEFAULT_AKS_CONTEXT"

# ── Confirmation ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${RED}════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${RED}  Kyverno Policy Demo — CLEANUP / TEARDOWN${NC}"
echo -e "${BOLD}${RED}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}  This will permanently delete:${NC}"
echo -e "  • All Kyverno policies and generated resources"
echo -e "  • The AKS cluster and all workloads"
echo -e "  • The Azure Resource Group and all contained resources"
echo ""
read -r -p "  Are you sure you want to continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo -e "\n  ${GREEN}Cleanup cancelled.${NC}"
  exit 0
fi

print_step() {
  echo -e "\n${CYAN}▶ $1${NC}"
}

# ── Step 1: Clean up Kubernetes resources ────────────────────────────────────
print_step "Removing test namespaces and sample apps..."
kubectl delete namespace demo --ignore-not-found --timeout=60s || true
kubectl delete namespace kyverno-demo-ns --ignore-not-found --timeout=60s || true
echo -e "  ${GREEN}✔${NC} Test namespaces removed."

# ── Step 2: Remove Kyverno policies ──────────────────────────────────────────
print_step "Removing Kyverno policies..."
kubectl delete -f "$SCRIPT_DIR/policies/04-cleanup/" --ignore-not-found || true
kubectl delete -f "$SCRIPT_DIR/policies/03-generation/" --ignore-not-found || true
kubectl delete -f "$SCRIPT_DIR/policies/02-mutation/" --ignore-not-found || true
kubectl delete -f "$SCRIPT_DIR/policies/01-validation/" --ignore-not-found || true
echo -e "  ${GREEN}✔${NC} Kyverno policies removed."

# ── Step 3: Terraform destroy ─────────────────────────────────────────────────
print_step "Destroying Azure infrastructure with Terraform..."
cd "$TF_DIR"

if [[ -f "terraform.tfstate" ]]; then
  TF_CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || true)
  if [[ -n "$TF_CLUSTER_NAME" ]]; then
    AKS_CONTEXT_NAME="$TF_CLUSTER_NAME"
  fi
fi

if [[ ! -f "terraform.tfstate" ]]; then
  echo -e "  ${YELLOW}⚠ No terraform.tfstate found — skipping terraform destroy.${NC}"
else
  terraform destroy -auto-approve
  echo -e "  ${GREEN}✔${NC} Azure resources destroyed."
fi

# ── Step 4: Clean up local kubeconfig context ─────────────────────────────────
print_step "Removing local kubectl context entries..."

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "$CURRENT_CONTEXT" == "$AKS_CONTEXT_NAME" ]]; then
  kubectl config unset current-context >/dev/null 2>&1 || true
fi

kubectl config delete-context "$AKS_CONTEXT_NAME" >/dev/null 2>&1 || true
kubectl config delete-cluster "$AKS_CONTEXT_NAME" >/dev/null 2>&1 || true
kubectl config delete-user "clusterUser_rg-kyverno-demo_${AKS_CONTEXT_NAME}" >/dev/null 2>&1 || true
kubectl config delete-user "clusterAdmin_rg-kyverno-demo_${AKS_CONTEXT_NAME}" >/dev/null 2>&1 || true

echo -e "  ${GREEN}✔${NC} Local kubeconfig entries cleaned (if present)."

# ── Complete ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Cleanup complete. All demo resources have been removed.${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}"
echo ""
