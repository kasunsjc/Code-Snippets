#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

DEMO="kustomize"
TF_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo)
      [[ $# -ge 2 ]] || { printf 'Missing value for --demo.\n' >&2; exit 1; }
      DEMO="$2"
      shift 2
      ;;
    -h|--help)
      printf 'Usage: bash deploy.sh [--demo setup|kustomize|helm|all] [terraform apply options]\n'
      printf 'Default: kustomize. Existing demos are retained when adding another demo.\n'
      exit 0
      ;;
    *)
      TF_ARGS+=("$1")
      shift
      ;;
  esac
done
case "$DEMO" in
  setup|kustomize|helm|all) ;;
  *) printf 'Invalid demo: %s. Choose setup, kustomize, helm, or all.\n' "$DEMO" >&2; exit 1 ;;
esac

for tool in az terraform kubectl jq; do
  command -v "$tool" >/dev/null || { printf 'Missing prerequisite: %s\n' "$tool" >&2; exit 1; }
done
az account show --output none
ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
export ARM_SUBSCRIPTION_ID

for namespace in Microsoft.ContainerService Microsoft.Kubernetes Microsoft.KubernetesConfiguration; do
  az provider register --namespace "$namespace" --wait --output none
done

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" fmt -check
terraform -chdir="$TF_DIR" validate
# Read resources rather than outputs so interrupted applies and older states are covered.
STATE="$(terraform -chdir="$TF_DIR" show -json)"
ENABLED_DEMOS="$(jq -cn --arg demo "$DEMO" --argjson state "$STATE" '
  [
    ($state.values.root_module.resources[]? |
      select(.type == "azurerm_kubernetes_flux_configuration") |
      if .name == "this" then "kustomize"
      elif .name == "kubeplay" then "helm"
      else empty end),
    (if $demo == "all" then "kustomize", "helm"
     elif $demo == "setup" then empty
     else $demo end)
  ] | unique
')"
printf 'Deploying shared infrastructure. Enabled demos: %s\n' "$ENABLED_DEMOS"
terraform -chdir="$TF_DIR" apply ${TF_ARGS[@]+"${TF_ARGS[@]}"} -var="enabled_demos=$ENABLED_DEMOS" -auto-approve

RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
KUBECONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/config}"
KUBECONFIG_PATH="${KUBECONFIG_PATH%%:*}"
umask 077
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
  --file "$KUBECONFIG_PATH" --overwrite-existing
chmod 600 "$KUBECONFIG_PATH"
kubectl config use-context "$CLUSTER_NAME"
printf 'AKS context %s is selected in %s.\n' "$CLUSTER_NAME" "$KUBECONFIG_PATH"

KUSTOMIZE_FLUX_CONFIGURATION="$(terraform -chdir="$TF_DIR" output -raw flux_configuration_name)"
if [[ -n "$KUSTOMIZE_FLUX_CONFIGURATION" ]]; then
  kubectl get gitrepositories.source.toolkit.fluxcd.io,kustomizations.kustomize.toolkit.fluxcd.io \
    --namespace cluster-config
fi
HELM_FLUX_CONFIGURATION="$(terraform -chdir="$TF_DIR" output -raw helm_flux_configuration_name)"
if [[ -n "$HELM_FLUX_CONFIGURATION" ]]; then
  kubectl get gitrepositories.source.toolkit.fluxcd.io,kustomizations.kustomize.toolkit.fluxcd.io \
    --namespace helm-demo-config
fi
printf '\nActive kubectl context: '
kubectl config current-context