#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

for tool in az terraform kubectl; do
  command -v "$tool" >/dev/null || { printf 'Missing prerequisite: %s\n' "$tool" >&2; exit 1; }
done
az account show --output none
: "${ARM_SUBSCRIPTION_ID:?Export ARM_SUBSCRIPTION_ID for your selected subscription first.}"
if [[ "$(az account show --query id --output tsv)" != "$ARM_SUBSCRIPTION_ID" ]]; then
  printf 'ARM_SUBSCRIPTION_ID must match the active Azure CLI subscription.\n' >&2
  exit 1
fi

for namespace in Microsoft.ContainerService Microsoft.Kubernetes Microsoft.KubernetesConfiguration; do
  az provider register --namespace "$namespace" --wait --output none
done

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" fmt -check
terraform -chdir="$TF_DIR" validate
terraform -chdir="$TF_DIR" apply "$@"

RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
export KUBECONFIG="${SCRIPT_DIR}/kubeconfig"
umask 077
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
  --file "$KUBECONFIG" --overwrite-existing
chmod 600 "$KUBECONFIG"

printf 'Flux is configured. Inspect source and reconciliation status for your external application repository:\n'
kubectl get gitrepositories.source.toolkit.fluxcd.io,kustomizations.kustomize.toolkit.fluxcd.io \
  --namespace cluster-config
printf '\nUse this kubeconfig for the walkthrough:\nexport KUBECONFIG="%s"\n' "$KUBECONFIG"