#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
ROUNDS=10
INTERVAL_SECONDS=1
VERIFY=false

usage() {
  cat <<EOF
Usage: bash $0 [--rounds 1-1000] [--interval 0-60] [--verify]
Generate matched retained/filtered AKS audit reads and payload-bearing writes.
  --rounds N     GET requests per ConfigMap (default: 10)
  --interval N   Seconds between read pairs (default: 1)
  --verify       Poll both workspaces after generation and assert the DCR policy
  -h, --help     Show help without accessing Azure
EOF
}

while (($#)); do
  case "$1" in
    --rounds|--interval)
      option="$1"
      value="${2:-}"
      if [[ ! "$value" =~ ^(0|[1-9][0-9]{0,3})$ ]]; then
        echo "$option requires a bounded integer." >&2
        exit 1
      fi
      if [[ "$option" == --rounds ]]; then
        if ((value < 1 || value > 1000)); then
          echo "--rounds must be between 1 and 1000." >&2
          exit 1
        fi
        ROUNDS="$value"
      else
        if ((value > 60)); then
          echo "--interval must be between 0 and 60." >&2
          exit 1
        fi
        INTERVAL_SECONDS="$value"
      fi
      shift 2
      ;;
    --verify) VERIFY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if (((ROUNDS - 1) * INTERVAL_SECONDS > 3600)); then
  echo "Keep the scheduled read duration within one hour so verification's two-hour window covers the run." >&2
  exit 1
fi
if [[ "$VERIFY" == true ]]; then
  command -v jq >/dev/null || { echo "Missing tool: jq" >&2; exit 1; }
fi
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

printf 'Run ID: %s\nGenerating %s retained GETs and %s filtered GETs.\n' "$RUN_ID" "$ROUNDS" "$ROUNDS"
kubectl -n "$NAMESPACE" create configmap "dcr-keep-$RUN_ID" --from-literal=message=synthetic-before
kubectl -n "$NAMESPACE" create configmap "dcr-drop-$RUN_ID" --from-literal=message=synthetic-noise
for ((round = 1; round <= ROUNDS; round++)); do
  kubectl -n "$NAMESPACE" get configmap "dcr-keep-$RUN_ID" -o name
  kubectl -n "$NAMESPACE" get configmap "dcr-drop-$RUN_ID" -o name
  if ((round < ROUNDS && INTERVAL_SECONDS > 0)); then
    sleep "$INTERVAL_SECONDS"
  fi
done
kubectl -n "$NAMESPACE" patch configmap "dcr-keep-$RUN_ID" --type merge \
  -p '{"data":{"message":"synthetic-after"}}'
# AKS audits ConfigMaps at Metadata level. An unbound Role supplies a payload
# without granting permissions to any identity or launching a workload.
kubectl -n "$NAMESPACE" create role "dcr-payload-$RUN_ID" --verb=get --resource=configmaps
kubectl -n "$NAMESPACE" delete role "dcr-payload-$RUN_ID"
kubectl -n "$NAMESPACE" delete configmap "dcr-keep-$RUN_ID" "dcr-drop-$RUN_ID"

printf '\nScenario run ID: %s\n' "$RUN_ID"
printf 'Expected baseline: >=%s keep GETs, >=%s drop GETs, and synthetic writes.\n' "$ROUNDS" "$ROUNDS"
printf 'Expected transformed: >=%s keep GETs, zero drop GETs, retained writes, and null payloads.\n' "$ROUNDS"
# Remove scenario resources before potentially long ingestion polling.
kubectl delete namespace "$NAMESPACE" --wait=false
CREATED_NAMESPACE=false
printf 'Verify after ingestion: EXPECTED_READS=%q bash %q %q\n' "$ROUNDS" "$SCRIPT_DIR/verify.sh" "$RUN_ID"
if [[ "$VERIFY" == true ]]; then
  EXPECTED_READS="$ROUNDS" bash "$SCRIPT_DIR/verify.sh" "$RUN_ID"
fi
