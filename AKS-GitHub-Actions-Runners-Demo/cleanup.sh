#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/common.sh"

if [[ "${1:-}" == "--help" && $# == 1 ]]; then
  echo "Usage: bash cleanup.sh (uninstalls ARC, destroys Azure resources, then removes local state/cache)"
  exit 0
fi
[[ $# == 0 ]] || fail "Unknown argument. Use --help."
require_tools az terraform kubectl kubelogin helm jq
[[ -f "$TF_DIR/terraform.tfstate" ]] || fail "No local demo state found. Do not delete state manually; recover it before cleanup."
select_subscription
terraform -chdir="$TF_DIR" init -input=false
subscription="$(tf_output subscription_id)"
resource_group="$(tf_output resource_group_name)"
node_resource_group="$(tf_output node_resource_group_name)"
export ARM_SUBSCRIPTION_ID="$subscription"

printf 'This removes ARC and destroys %s and %s, including ALL Azure Files cache/workspace data.\n' "$resource_group" "$node_resource_group"
read -r -p "Stop workflow submissions and wait for running jobs to finish. Type yes to destroy: " confirmation
[[ "$confirmation" == "yes" ]] || { echo "Cleanup cancelled."; exit 0; }

# Keep the controller alive until runners have deregistered from GitHub.
if [[ "$(az group exists --subscription "$subscription" --name "$resource_group")" == "true" ]] &&
  [[ "$(az aks list --subscription "$subscription" --resource-group "$resource_group" \
    --query "length([?name=='$(tf_output aks_cluster_name)'])" --output tsv)" != "0" ]]; then
  connect_cluster
  for release_namespace in "$RUNNER_RELEASE:$RUNNER_NAMESPACE" "$CONTROLLER_RELEASE:$CONTROLLER_NAMESPACE"; do
    release="${release_namespace%%:*}"
    namespace="${release_namespace##*:}"
    if [[ "$(helm list --namespace "$namespace" --all --filter "^${release}$" --output json | jq length)" != "0" ]]; then
      helm uninstall "$release" --namespace "$namespace" --wait --timeout 15m
    fi
  done
fi

terraform -chdir="$TF_DIR" destroy -input=false -auto-approve
for group in "$resource_group" "$node_resource_group"; do
  [[ "$(az group exists --subscription "$subscription" --name "$group")" == "false" ]] ||
    fail "Resource group $group still exists. Local state/cache retained for recovery."
done

rm -f "$TF_DIR/terraform.tfstate" "$TF_DIR/terraform.tfstate.backup" \
  "$TF_DIR/demo.tfplan" "$TF_DIR/.terraform.lock.hcl" "$KUBECONFIG"
rm -rf "$TF_DIR/.terraform"
echo "Azure resource groups are gone; local state, kubeconfig and provider cache removed."
echo "Revoke the demo PAT or uninstall the GitHub App if no longer needed."
