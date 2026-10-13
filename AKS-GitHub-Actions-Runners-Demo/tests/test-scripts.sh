#!/usr/bin/env bash
set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
fixture="$test_dir/demo"
mkdir -p "$fixture/scripts" "$fixture/terraform/.terraform" "$fixture/arc" "$test_dir/bin"
cp "$DEMO_DIR/deploy.sh" "$DEMO_DIR/cleanup.sh" "$fixture/"
cp "$DEMO_DIR/scripts/"*.sh "$fixture/scripts/"
cp "$DEMO_DIR/arc/"*.yaml "$fixture/arc/"
cp "$DEMO_DIR/tests/mock-tool.sh" "$test_dir/bin/mock-tool"
chmod +x "$test_dir/bin/mock-tool"
for tool in az terraform kubectl kubelogin helm openssl sleep; do
  ln -s mock-tool "$test_dir/bin/$tool"
done
export PATH="$test_dir/bin:$PATH"
export MOCK_LOG="$test_dir/commands.log"
export MOCK_DESTROYED="$test_dir/destroyed"
export MOCK_MANIFEST="$test_dir/storage.yaml"
export GITHUB_AUTH_MODE=pat
export GITHUB_CONFIG_URL=https://github.com/example/demo
export GITHUB_PAT=test-token-not-a-real-credential
export TMPDIR="$test_dir"
unset ARM_SUBSCRIPTION_ID GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY_FILE GITHUB_RUNNER_GROUP
touch "$MOCK_LOG"

expect_failure() {
  local expected="$1"
  shift
  if "$@" > "$test_dir/output" 2>&1; then
    echo "FAIL: expected failure: $*" >&2
    exit 1
  fi
  grep -q "$expected" "$test_dir/output" || { cat "$test_dir/output"; exit 1; }
}

expect_absent() {
  if grep -q -- "$1" "$2"; then
    echo "FAIL: unexpected content: $1" >&2
    exit 1
  fi
}

for script in deploy.sh cleanup.sh scripts/install-arc.sh; do
  bash "$fixture/$script" --help >/dev/null
  expect_failure "Unknown argument" bash "$fixture/$script" --invalid
done
[[ ! -s "$MOCK_LOG" ]] || { echo "FAIL: help/invalid arguments invoked tools"; exit 1; }
expect_failure "Copy terraform.tfvars.example" bash "$fixture/deploy.sh"
touch "$fixture/terraform/terraform.tfvars"
expect_failure "Set GITHUB_CONFIG_URL" env GITHUB_CONFIG_URL=https://invalid.example bash "$fixture/deploy.sh"
expect_failure "Set GITHUB_PAT" env GITHUB_PAT= bash "$fixture/deploy.sh"
expect_failure "GITHUB_AUTH_MODE must be" env GITHUB_AUTH_MODE=invalid bash "$fixture/deploy.sh"
expect_failure "Set the numeric GITHUB_APP_ID" env GITHUB_AUTH_MODE=app bash "$fixture/deploy.sh"
expect_failure "GitHub App authentication is not supported" env \
  GITHUB_CONFIG_URL=https://github.com/enterprises/example-enterprise GITHUB_AUTH_MODE=app \
  bash "$fixture/deploy.sh"
expect_failure "Set GITHUB_RUNNER_GROUP" env \
  GITHUB_CONFIG_URL=https://github.com/enterprises/example-enterprise \
  bash "$fixture/deploy.sh"
expect_failure "not repository registration" env GITHUB_RUNNER_GROUP=aks-enterprise-runners bash "$fixture/deploy.sh"
expect_failure "Enterprise registration requires" env GITHUB_CONFIG_URL=https://github.com/enterprises bash "$fixture/deploy.sh"
expect_failure "GITHUB_RUNNER_GROUP must be" env \
  GITHUB_CONFIG_URL=https://github.com/enterprises/example-enterprise GITHUB_RUNNER_GROUP='invalid,group' \
  bash "$fixture/deploy.sh"
[[ ! -s "$MOCK_LOG" ]] || { echo "FAIL: invalid configuration invoked tools"; exit 1; }

bash "$fixture/deploy.sh" <<< no > "$test_dir/output"
expect_absent "terraform .*apply" "$MOCK_LOG"
expect_absent "helm " "$MOCK_LOG"

: > "$MOCK_LOG"
bash "$fixture/scripts/install-arc.sh" > "$test_dir/output"
grep -q "helm upgrade --install arc-controller .*--version 0.15.0" "$MOCK_LOG"
grep -q "helm upgrade --install aks-arc-runners .*--version 0.15.0" "$MOCK_LOG"
grep -q "kubectl apply --server-side --field-manager=arc-demo" "$MOCK_LOG"
grep -q "kubectl wait --namespace arc-systems" "$MOCK_LOG"
expect_absent "$GITHUB_PAT" "$MOCK_LOG"
expect_absent "$GITHUB_PAT" "$test_dir/output"
grep -q "pod-security.kubernetes.io/enforce=baseline" "$MOCK_LOG"
expect_absent "enforce=privileged" "$MOCK_LOG"
grep -q "job-hook-configmap.yaml" "$MOCK_LOG"
grep -q "kubectl apply -f .*/arc/runner-nodepool.yaml" "$MOCK_LOG"
grep -q "pvc/nuget-cache" "$MOCK_LOG"
grep -q 'storageAccount: "stghatest123456"' "$MOCK_MANIFEST"
grep -q 'storeAccountKey: "false"' "$MOCK_MANIFEST"
grep -q "persistentVolumeReclaimPolicy: Retain" "$MOCK_MANIFEST"
expect_absent "kind: StorageClass" "$MOCK_MANIFEST"
grep -q "kubectl delete storageclass arc-azurefile-premium" "$MOCK_LOG"
expect_absent "nodeStageSecretRef" "$MOCK_MANIFEST"
expect_absent "kubectl patch pv" "$MOCK_LOG"

: > "$MOCK_LOG"
MOCK_PV_RELEASED=1 bash "$fixture/scripts/install-storage.sh" > "$test_dir/output"
grep -q "kubectl patch pv arc-nuget-cache --type=merge" "$MOCK_LOG"

: > "$MOCK_LOG"
GITHUB_CONFIG_URL=https://github.com/enterprises/example-enterprise \
  GITHUB_RUNNER_GROUP=aks-enterprise-runners \
  bash "$fixture/scripts/install-arc.sh" > "$test_dir/output"
grep -q -- "--set-string githubConfigUrl=https://github.com/enterprises/example-enterprise" "$MOCK_LOG"
grep -q -- "--set-string runnerGroup=aks-enterprise-runners" "$MOCK_LOG"
expect_absent "$GITHUB_PAT" "$MOCK_LOG"

: > "$MOCK_LOG"
GITHUB_CONFIG_URL=https://github.com/example-org GITHUB_RUNNER_GROUP=trusted-builds \
  bash "$fixture/scripts/install-arc.sh" > "$test_dir/output"
grep -q -- "--set-string runnerGroup=trusted-builds" "$MOCK_LOG"

: > "$MOCK_LOG"
touch "$test_dir/app.pem"
GITHUB_AUTH_MODE=app GITHUB_APP_ID=123456 GITHUB_APP_INSTALLATION_ID=654321 \
  GITHUB_APP_PRIVATE_KEY_FILE="$test_dir/app.pem" \
  bash "$fixture/scripts/install-arc.sh" > "$test_dir/output"
grep -q -- "--from-file=github_app_private_key=" "$MOCK_LOG"
expect_absent "--from-file=github_token=" "$MOCK_LOG"

: > "$MOCK_LOG"
bash "$fixture/deploy.sh" <<< yes > "$test_dir/output"
grep -q "terraform .*apply -input=false demo.tfplan" "$MOCK_LOG"
grep -q "helm upgrade --install aks-arc-runners" "$MOCK_LOG"
grep -q "AKS portal:" "$test_dir/output"

expect_failure "No local demo state" bash "$fixture/cleanup.sh"
touch "$fixture/terraform/terraform.tfstate" "$fixture/terraform/terraform.tfstate.backup"
: > "$MOCK_LOG"
bash "$fixture/cleanup.sh" <<< no > "$test_dir/output"
expect_absent "terraform .*destroy" "$MOCK_LOG"
[[ -f "$fixture/terraform/terraform.tfstate" ]]

: > "$MOCK_LOG"
expect_failure "" env MOCK_DESTROY_FAIL=1 bash "$fixture/cleanup.sh" <<< yes
[[ -f "$fixture/terraform/terraform.tfstate" && -d "$fixture/terraform/.terraform" ]]
runner_line="$(grep -n "helm uninstall aks-arc-runners" "$MOCK_LOG" | cut -d: -f1)"
controller_line="$(grep -n "helm uninstall arc-controller" "$MOCK_LOG" | cut -d: -f1)"
[[ "$runner_line" -lt "$controller_line" ]]
nodepool_line="$(grep -n "kubectl delete nodepools.karpenter.sh github-actions" "$MOCK_LOG" | cut -d: -f1)"
[[ "$controller_line" -lt "$nodepool_line" ]]

: > "$MOCK_LOG"
expect_failure "still exists" env MOCK_GROUP_LEFT=1 bash "$fixture/cleanup.sh" <<< yes
[[ -f "$fixture/terraform/terraform.tfstate" && -d "$fixture/terraform/.terraform" ]]
rm -f "$MOCK_DESTROYED"

: > "$MOCK_LOG"
bash "$fixture/cleanup.sh" <<< yes > "$test_dir/output"
[[ ! -f "$fixture/terraform/terraform.tfstate" && ! -d "$fixture/terraform/.terraform" && ! -f "$fixture/.kube/config" ]]
grep -q "Azure resource groups are gone" "$test_dir/output"

rm -f "$MOCK_DESTROYED"
touch "$fixture/terraform/terraform.tfstate"
: > "$MOCK_LOG"
MOCK_CLUSTER_GONE=1 bash "$fixture/cleanup.sh" <<< yes > "$test_dir/output"
expect_absent "helm " "$MOCK_LOG"
grep -q "terraform .*destroy" "$MOCK_LOG"
echo "PASS: enterprise/org/repo registration, Karpenter NodePool, configuration guards, Files storage, secret handling, cancellation and teardown recovery."
