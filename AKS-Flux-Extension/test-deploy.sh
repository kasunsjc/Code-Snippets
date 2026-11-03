#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -f "$TEST_DIR/commands" "$TEST_DIR/config" "$TEST_DIR/output"; rmdir "$TEST_DIR"' EXIT
export TEST_DIR
export KUBECONFIG="$TEST_DIR/config"

az() {
  printf 'az %s\n' "$*" >> "$TEST_DIR/commands"
  case "$1 $2" in
    "account show") printf 'test-subscription\n' ;;
    "aks get-credentials") : > "$KUBECONFIG" ;;
  esac
}

terraform() {
  printf 'terraform %s\n' "$*" >> "$TEST_DIR/commands"
  case "$2" in
    show)
      [[ "${FAIL_STATE:-false}" == false ]] || return 1
      printf '%s\n' "$MOCK_STATE"
      ;;
    output)
      case "$4" in
        resource_group_name) printf 'rg-flux-demo\n' ;;
        cluster_name) printf 'aks-flux-demo\n' ;;
        flux_configuration_name)
          if [[ "$EXPECTED" == *kustomize* ]]; then printf 'cluster-config\n'; fi
          ;;
        helm_flux_configuration_name)
          if [[ "$EXPECTED" == *helm* ]]; then printf 'helm-demo-config\n'; fi
          ;;
        *) return 1 ;;
      esac
      ;;
  esac
}

kubectl() {
  printf 'kubectl %s\n' "$*" >> "$TEST_DIR/commands"
}
export -f az terraform kubectl

run_case() {
  local demo="$1" resources="$2"
  export EXPECTED="$3"
  export MOCK_STATE="{\"values\":{\"root_module\":{\"resources\":$resources}}}"
  : > "$TEST_DIR/commands"
  bash "$SCRIPT_DIR/deploy.sh" --demo "$demo" -parallelism=2 > "$TEST_DIR/output"
  grep -Fq -- "-var=enabled_demos=$EXPECTED" "$TEST_DIR/commands"
  grep -Fq -- '-parallelism=2' "$TEST_DIR/commands"
  grep -Fq 'kubectl config use-context aks-flux-demo' "$TEST_DIR/commands"
  if [[ "$EXPECTED" == *kustomize* ]]; then
    grep -Fq -- '--namespace cluster-config' "$TEST_DIR/commands"
  elif grep -Fq -- '--namespace cluster-config' "$TEST_DIR/commands"; then
    printf 'Unexpected Kustomize inspection for %s\n' "$demo" >&2
    exit 1
  fi
  if [[ "$EXPECTED" == *helm* ]]; then
    grep -Fq -- '--namespace helm-demo-config' "$TEST_DIR/commands"
  elif grep -Fq -- '--namespace helm-demo-config' "$TEST_DIR/commands"; then
    printf 'Unexpected Helm inspection for %s\n' "$demo" >&2
    exit 1
  fi
  printf 'PASS: --demo %s enables %s\n' "$demo" "$EXPECTED"
}

run_case setup '[]' '[]'
run_case kustomize '[]' '["kustomize"]'
run_case helm '[]' '["helm"]'
run_case all '[]' '["helm","kustomize"]'
run_case helm '[{"type":"azurerm_kubernetes_flux_configuration","name":"this"}]' '["helm","kustomize"]'
run_case kustomize '[{"type":"azurerm_kubernetes_flux_configuration","name":"kubeplay","index":0}]' '["helm","kustomize"]'
run_case setup '[{"type":"azurerm_kubernetes_flux_configuration","name":"kubeplay","index":0}]' '["helm"]'

export MOCK_STATE='{}' EXPECTED='["kustomize"]'
: > "$TEST_DIR/commands"
bash "$SCRIPT_DIR/deploy.sh" > "$TEST_DIR/output"
grep -Fq -- '-var=enabled_demos=["kustomize"]' "$TEST_DIR/commands"
printf 'PASS: default remains Kustomize with an empty state\n'

for argument in invalid --demo; do
  : > "$TEST_DIR/commands"
  if [[ "$argument" == invalid ]]; then
    args=(--demo invalid)
  else
    args=(--demo)
  fi
  if bash "$SCRIPT_DIR/deploy.sh" "${args[@]}" > "$TEST_DIR/output" 2>&1; then
    printf 'Expected argument validation failure\n' >&2
    exit 1
  fi
  [[ ! -s "$TEST_DIR/commands" ]]
done
printf 'PASS: invalid selections fail before Azure or Terraform calls\n'

export FAIL_STATE=true
: > "$TEST_DIR/commands"
if bash "$SCRIPT_DIR/deploy.sh" --demo helm > "$TEST_DIR/output" 2>&1; then
  printf 'Expected state-read failure\n' >&2
  exit 1
fi
if grep -Fq ' apply ' "$TEST_DIR/commands"; then
  printf 'Apply must not run when state cannot be read\n' >&2
  exit 1
fi
printf 'PASS: state-read failure prevents apply\n'
