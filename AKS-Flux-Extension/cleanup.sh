#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

for tool in az terraform jq; do
  command -v "$tool" >/dev/null || { printf 'Missing prerequisite: %s\n' "$tool" >&2; exit 1; }
done
az account show --output none
ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
export ARM_SUBSCRIPTION_ID

printf 'This destroys the demo AKS cluster, Flux configuration, extension and resource groups.\n'
read -r -p 'Type destroy to continue: ' confirmation
[[ "$confirmation" == "destroy" ]] || { printf 'Cancelled.\n'; exit 0; }

terraform -chdir="$TF_DIR" init -input=false
OUTPUTS="$(terraform -chdir="$TF_DIR" output -json)"
RESOURCE_GROUP="$(jq -r '.resource_group_name.value // empty' <<< "$OUTPUTS")"
CLUSTER_NAME="$(jq -r '.cluster_name.value // empty' <<< "$OUTPUTS")"
NODE_RESOURCE_GROUP="$(jq -r '.node_resource_group_name.value // empty' <<< "$OUTPUTS")"
terraform -chdir="$TF_DIR" destroy "$@" -auto-approve

KUBECONFIG_PATH="${SCRIPT_DIR}/kubeconfig"
if [[ -f "$KUBECONFIG_PATH" && -n "$CLUSTER_NAME" ]] && command -v kubectl >/dev/null 2>&1; then
  export KUBECONFIG="$KUBECONFIG_PATH"
  CONFIG="$(kubectl config view --raw -o json 2>/dev/null || true)"
  CONTEXT_DETAILS="$(jq -r --arg name "$CLUSTER_NAME" \
    '.contexts[]? | select(.name == $name) | [.context.cluster // "", .context.user // ""] | @tsv' \
    <<< "$CONFIG" 2>/dev/null || true)"
  if [[ -n "$CONTEXT_DETAILS" ]]; then
    IFS=$'\t' read -r CLUSTER_CONFIG_NAME USER_CONFIG_NAME <<< "$CONTEXT_DETAILS"
    kubectl config delete-context "$CLUSTER_NAME" >/dev/null 2>&1 || true
    if [[ -n "$CLUSTER_CONFIG_NAME" ]] &&
      ! kubectl config view --raw -o json 2>/dev/null |
        jq -e --arg name "$CLUSTER_CONFIG_NAME" 'any(.contexts[]?; .context.cluster == $name)' >/dev/null; then
      kubectl config delete-cluster "$CLUSTER_CONFIG_NAME" >/dev/null 2>&1 || true
    fi
    if [[ -n "$USER_CONFIG_NAME" ]] &&
      ! kubectl config view --raw -o json 2>/dev/null |
        jq -e --arg name "$USER_CONFIG_NAME" 'any(.contexts[]?; .context.user == $name)' >/dev/null; then
      kubectl config delete-user "$USER_CONFIG_NAME" >/dev/null 2>&1 || true
    fi
    printf 'Removed demo context and unreferenced cluster/user entries from %s; kubeconfig file retained.\n' "$KUBECONFIG_PATH"
  fi
fi

for group in "$RESOURCE_GROUP" "$NODE_RESOURCE_GROUP"; do
  if [[ -n "$group" ]] && [[ "$(az group exists --name "$group" --output tsv)" != "false" ]]; then
    printf 'Resource group %s still exists. Retaining state; investigate before removing it.\n' "$group" >&2
    exit 1
  fi
done

rm -rf "${TF_DIR}/.terraform"
rm -f "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup"
printf 'Terraform destroy completed; local state and provider cache removed.\n'