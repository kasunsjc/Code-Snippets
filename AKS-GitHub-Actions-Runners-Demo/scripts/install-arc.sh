#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ "${1:-}" == "--help" && $# == 1 ]]; then
  echo "Usage: bash scripts/install-arc.sh (installs or upgrades ARC on this demo's AKS Automatic cluster)"
  exit 0
fi
[[ $# == 0 ]] || fail "Unknown argument. Use --help."
require_tools az terraform kubectl kubelogin helm
validate_github_config
connect_cluster

kubectl create namespace "$CONTROLLER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$RUNNER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$RUNNER_NAMESPACE" pod-security.kubernetes.io/enforce=baseline --overwrite
# Dedicated Karpenter NodePool: AKS Automatic provisions tainted runner nodes on demand.
kubectl apply -f "$DEMO_DIR/arc/runner-nodepool.yaml"
bash "$DEMO_DIR/scripts/install-storage.sh"
kubectl apply -f "$DEMO_DIR/arc/job-hook-configmap.yaml"

umask 077
secret_dir="$(mktemp -d)"
trap 'rm -rf "$secret_dir"' EXIT
secret_args=()
if [[ "${GITHUB_AUTH_MODE:-app}" == "app" ]]; then
  printf '%s' "$GITHUB_APP_ID" > "$secret_dir/github_app_id"
  printf '%s' "$GITHUB_APP_INSTALLATION_ID" > "$secret_dir/github_app_installation_id"
  secret_args+=("--from-file=github_app_id=$secret_dir/github_app_id")
  secret_args+=("--from-file=github_app_installation_id=$secret_dir/github_app_installation_id")
  secret_args+=("--from-file=github_app_private_key=$GITHUB_APP_PRIVATE_KEY_FILE")
else
  printf '%s' "$GITHUB_PAT" > "$secret_dir/github_token"
  secret_args+=("--from-file=github_token=$secret_dir/github_token")
fi
kubectl create secret generic github-auth --namespace "$RUNNER_NAMESPACE" \
  "${secret_args[@]}" --dry-run=client -o yaml |
  kubectl apply --server-side --field-manager=arc-demo -f -

helm upgrade --install "$CONTROLLER_RELEASE" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version "$ARC_VERSION" --namespace "$CONTROLLER_NAMESPACE" \
  --values "$DEMO_DIR/arc/controller-values.yaml" --wait --timeout 10m
runner_config_args=("--set-string" "githubConfigUrl=$GITHUB_CONFIG_URL")
if [[ -n "${GITHUB_RUNNER_GROUP:-}" ]]; then
  runner_config_args+=("--set-string" "runnerGroup=$GITHUB_RUNNER_GROUP")
fi
helm upgrade --install "$RUNNER_RELEASE" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version "$ARC_VERSION" --namespace "$RUNNER_NAMESPACE" \
  --values "$DEMO_DIR/arc/runner-values.yaml" \
  "${runner_config_args[@]}" --wait --timeout 10m

listener_selector="app.kubernetes.io/component=runner-scale-set-listener,actions.github.com/scale-set-name=$RUNNER_RELEASE"
for attempt in {1..30}; do
  if [[ -n "$(kubectl get pods --namespace "$CONTROLLER_NAMESPACE" --selector="$listener_selector" -o name)" ]]; then
    break
  fi
  printf 'Waiting for ARC to create the listener (%s/30)...\n' "$attempt"
  sleep 10
done
kubectl wait --namespace "$CONTROLLER_NAMESPACE" pod \
  --selector="$listener_selector" \
  --for=condition=Ready --timeout=300s
kubectl get autoscalingrunnersets.actions.github.com --namespace "$RUNNER_NAMESPACE"
echo "ARC is ready. Dispatch the sample workflow with runs-on: aks-arc-runners."
