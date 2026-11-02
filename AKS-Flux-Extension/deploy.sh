#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

for tool in az terraform kubectl; do
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
terraform -chdir="$TF_DIR" apply "$@" -auto-approve

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

printf 'Flux is configured. Inspect source and reconciliation status for your external application repository:\n'
kubectl get gitrepositories.source.toolkit.fluxcd.io,kustomizations.kustomize.toolkit.fluxcd.io \
  --namespace cluster-config
HELM_FLUX_CONFIGURATION="$(terraform -chdir="$TF_DIR" output -raw helm_flux_configuration_name)"
if [[ -n "$HELM_FLUX_CONFIGURATION" ]]; then
  kubectl get gitrepositories.source.toolkit.fluxcd.io,kustomizations.kustomize.toolkit.fluxcd.io \
    --namespace helm-demo-config
fi
printf '\nActive kubectl context: '
kubectl config current-context