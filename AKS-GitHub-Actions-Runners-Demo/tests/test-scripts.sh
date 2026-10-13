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
export GITHUB_AUTH_MODE=pat
export GITHUB_CONFIG_URL=https://github.com/example/demo
export GITHUB_PAT=test-token-not-a-real-credential
export TMPDIR="$test_dir"
unset ARM_SUBSCRIPTION_ID GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY_FILE
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
[[ ! -s "$MOCK_LOG" ]] || { echo "FAIL: invalid configuration invoked tools"; exit 1; }

bash "$fixture/deploy.sh" <<< no > "$test_dir/output"
! grep -q "terraform .*apply" "$MOCK_LOG"
! grep -q "helm " "$MOCK_LOG"

: > "$MOCK_LOG"
bash "$fixture/scripts/install-arc.sh" > "$test_dir/output"
grep -q "helm upgrade --install arc-controller .*--version 0.15.0" "$MOCK_LOG"
grep -q "helm upgrade --install aks-arc-runners .*--version 0.15.0" "$MOCK_LOG"
grep -q "kubectl apply --server-side --field-manager=arc-demo" "$MOCK_LOG"
grep -q "kubectl wait --namespace arc-systems" "$MOCK_LOG"
! grep -q "$GITHUB_PAT" "$MOCK_LOG"
! grep -q "$GITHUB_PAT" "$test_dir/output"

: > "$MOCK_LOG"
touch "$test_dir/app.pem"
GITHUB_AUTH_MODE=app GITHUB_APP_ID=123456 GITHUB_APP_INSTALLATION_ID=654321 \
  GITHUB_APP_PRIVATE_KEY_FILE="$test_dir/app.pem" \
  bash "$fixture/scripts/install-arc.sh" > "$test_dir/output"
grep -q -- "--from-file=github_app_private_key=" "$MOCK_LOG"
! grep -q -- "--from-file=github_token=" "$MOCK_LOG"

: > "$MOCK_LOG"
bash "$fixture/deploy.sh" <<< yes > "$test_dir/output"
grep -q "terraform .*apply -input=false demo.tfplan" "$MOCK_LOG"
grep -q "helm upgrade --install aks-arc-runners" "$MOCK_LOG"
grep -q "AKS portal:" "$test_dir/output"

expect_failure "No local demo state" bash "$fixture/cleanup.sh"
touch "$fixture/terraform/terraform.tfstate" "$fixture/terraform/terraform.tfstate.backup"
: > "$MOCK_LOG"
bash "$fixture/cleanup.sh" <<< no > "$test_dir/output"
! grep -q "terraform .*destroy" "$MOCK_LOG"
[[ -f "$fixture/terraform/terraform.tfstate" ]]

: > "$MOCK_LOG"
expect_failure "" env MOCK_DESTROY_FAIL=1 bash "$fixture/cleanup.sh" <<< yes
[[ -f "$fixture/terraform/terraform.tfstate" && -d "$fixture/terraform/.terraform" ]]
runner_line="$(grep -n "helm uninstall aks-arc-runners" "$MOCK_LOG" | cut -d: -f1)"
controller_line="$(grep -n "helm uninstall arc-controller" "$MOCK_LOG" | cut -d: -f1)"
[[ "$runner_line" -lt "$controller_line" ]]

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
! grep -q "helm " "$MOCK_LOG"
grep -q "terraform .*destroy" "$MOCK_LOG"
echo "PASS: configuration guards, secret handling, listener namespace, cancellation, teardown order and failure recovery."
