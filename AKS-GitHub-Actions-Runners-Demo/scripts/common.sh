#!/usr/bin/env bash
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$DEMO_DIR/terraform"
export KUBECONFIG="$DEMO_DIR/.kube/config"
ARC_VERSION="0.15.0"
CONTROLLER_NAMESPACE="arc-systems"
RUNNER_NAMESPACE="arc-runners"
CONTROLLER_RELEASE="arc-controller"
RUNNER_RELEASE="aks-arc-runners"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || fail "Install '$tool' before continuing."
  done
}

tf_output() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

select_subscription() {
  az account show --output none || fail "Sign in with az login first."
  export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
}

connect_cluster() {
  local subscription resource_group cluster attempt
  subscription="$(tf_output subscription_id)"
  resource_group="$(tf_output resource_group_name)"
  cluster="$(tf_output aks_cluster_name)"
  umask 077
  mkdir -p "$DEMO_DIR/.kube"
  az aks get-credentials --subscription "$subscription" \
    --resource-group "$resource_group" --name "$cluster" \
    --file "$KUBECONFIG" --overwrite-existing
  kubelogin convert-kubeconfig -l azurecli
  for attempt in {1..30}; do
    if [[ "$(kubectl auth can-i create namespaces)" == "yes" ]]; then
      return
    fi
    printf 'Waiting for AKS RBAC propagation (%s/30)...\n' "$attempt"
    sleep 10
  done
  fail "AKS access did not become ready. Check the API allowlist (if set), Azure subscription/tenant and RBAC assignment."
}

validate_github_config() {
  local enterprise=false
  [[ "${GITHUB_CONFIG_URL:-}" =~ ^https://github\.com/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?$ ]] ||
    fail "Set GITHUB_CONFIG_URL to https://github.com/enterprises/SLUG, /OWNER/REPO or /ORG (no trailing slash)."
  if [[ "$GITHUB_CONFIG_URL" == "https://github.com/enterprises" || "$GITHUB_CONFIG_URL" == "https://github.com/enterprises/"* ]]; then
    [[ "$GITHUB_CONFIG_URL" =~ ^https://github\.com/enterprises/[A-Za-z0-9-]+$ ]] ||
      fail "Enterprise registration requires https://github.com/enterprises/SLUG."
    enterprise=true
    [[ "${GITHUB_AUTH_MODE:-app}" == "pat" ]] ||
      fail "Enterprise runners require GITHUB_AUTH_MODE=pat and a PAT (classic); GitHub App authentication is not supported."
    [[ -n "${GITHUB_RUNNER_GROUP:-}" ]] ||
      fail "Set GITHUB_RUNNER_GROUP to an existing enterprise runner group with restricted organization access."
  fi
  if [[ -n "${GITHUB_RUNNER_GROUP:-}" ]]; then
    [[ "$GITHUB_RUNNER_GROUP" =~ ^[A-Za-z0-9][A-Za-z0-9._\ -]{0,99}$ ]] ||
      fail "GITHUB_RUNNER_GROUP must be 1-100 letters, digits, spaces, dots, underscores or hyphens, starting with a letter or digit."
    [[ "$GITHUB_CONFIG_URL" != "https://github.com/"*"/"* || "$enterprise" == "true" ]] ||
      fail "Runner groups apply to organization or enterprise registration, not repository registration."
  fi
  case "${GITHUB_AUTH_MODE:-app}" in
    app)
      [[ "${GITHUB_APP_ID:-}" =~ ^[0-9]+$ ]] || fail "Set the numeric GITHUB_APP_ID."
      [[ "${GITHUB_APP_INSTALLATION_ID:-}" =~ ^[0-9]+$ ]] || fail "Set the numeric GITHUB_APP_INSTALLATION_ID."
      [[ -r "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ]] || fail "Set GITHUB_APP_PRIVATE_KEY_FILE to a readable PEM file outside the repository."
      require_tools openssl
      openssl pkey -in "$GITHUB_APP_PRIVATE_KEY_FILE" -passin pass: -noout >/dev/null ||
        fail "The GitHub App private key is not valid."
      ;;
    pat)
      [[ -n "${GITHUB_PAT:-}" ]] || fail "Set GITHUB_PAT without pasting it into source files."
      ;;
    *) fail "GITHUB_AUTH_MODE must be app or pat." ;;
  esac
}
