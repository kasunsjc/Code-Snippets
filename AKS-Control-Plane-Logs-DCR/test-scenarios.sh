#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
for tool in terraform az kubectl; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"
RUN_ID="$(date -u +%Y%m%d%H%M%S)-$RANDOM"
NAMESPACE="aks-dcr-demo"
TEMP_DIR="$(mktemp -d)"
export KUBECONFIG="$TEMP_DIR/config"
CREATED_NAMESPACE=false

cleanup() {
  if [[ "$CREATED_NAMESPACE" == true ]]; then
    kubectl delete namespace "$NAMESPACE" --wait=false >/dev/null || echo "Delete namespace $NAMESPACE manually." >&2
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

az aks get-credentials --subscription "$SUBSCRIPTION_ID" --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" --file "$KUBECONFIG" --output none
# A create (not apply) refuses to reuse or delete a pre-existing namespace.
kubectl create namespace "$NAMESPACE"
CREATED_NAMESPACE=true

kubectl -n "$NAMESPACE" create configmap "dcr-keep-$RUN_ID" --from-literal=message=synthetic-before
kubectl -n "$NAMESPACE" create configmap "dcr-drop-$RUN_ID" --from-literal=message=synthetic-noise
for _ in {1..10}; do
  kubectl -n "$NAMESPACE" get configmap "dcr-keep-$RUN_ID" -o name
  kubectl -n "$NAMESPACE" get configmap "dcr-drop-$RUN_ID" -o name
done
kubectl -n "$NAMESPACE" patch configmap "dcr-keep-$RUN_ID" --type merge \
  -p '{"data":{"message":"synthetic-after"}}'
# AKS audits ConfigMaps at Metadata level. An unbound Role supplies a payload
# without granting permissions to any identity or launching a workload.
kubectl -n "$NAMESPACE" create role "dcr-payload-$RUN_ID" --verb=get --resource=configmaps
kubectl -n "$NAMESPACE" delete role "dcr-payload-$RUN_ID"
kubectl -n "$NAMESPACE" delete configmap "dcr-keep-$RUN_ID" "dcr-drop-$RUN_ID"

printf '\nScenario run ID: %s\n' "$RUN_ID"
printf 'Verify after ingestion: bash %q %q\n' "$SCRIPT_DIR/verify.sh" "$RUN_ID"
