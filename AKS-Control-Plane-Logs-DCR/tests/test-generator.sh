#!/usr/bin/env bash
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
export MOCK_LOG="$TEMP_DIR/commands"
export MOCK_DEFAULT_KUBECONFIG="$TEMP_DIR/user-config"
printf 'leave unchanged\n' > "$MOCK_DEFAULT_KUBECONFIG"
export KUBECONFIG="$MOCK_DEFAULT_KUBECONFIG"

cat > "$TEMP_DIR/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
tool="${0##*/}"
printf '%s %s\n' "$tool" "$*" >> "$MOCK_LOG"
case "$tool" in
  terraform)
    case "${*: -1}" in
      resource_group_name) echo rg-demo ;;
      cluster_name) echo aks-demo ;;
      subscription_id) echo 00000000-0000-0000-0000-000000000000 ;;
      cluster_id) echo /subscriptions/demo/resourceGroups/rg-demo/providers/Microsoft.ContainerService/managedClusters/aks-demo ;;
      baseline_workspace_customer_id) echo baseline ;;
      transformed_workspace_customer_id) echo transformed ;;
      *) exit 1 ;;
    esac
    ;;
  kubectl)
    [[ "$KUBECONFIG" != "$MOCK_DEFAULT_KUBECONFIG" ]]
    if [[ "${FAIL_NAMESPACE:-false}" == true && "$*" == "create namespace aks-dcr-demo" ]]; then
      exit 1
    fi
    ;;
  az)
    if [[ "$1" == rest ]]; then
      if [[ "$*" == *AKSControlPlane* ]]; then
        echo '{"tables":[{"rows":[[5,0]]}]}'
      elif [[ "$*" == *"/workspaces/baseline/"* ]]; then
        echo '{"tables":[{"rows":[[3,3,3,1,3,1,1,1]]}]}'
      else
        printf '{"tables":[{"rows":[[3,%s,3,1,3,0,1,0]]}]}\n' "${TRANSFORMED_DROP_READS:-0}"
      fi
    fi
    ;;
esac
MOCK
chmod +x "$TEMP_DIR/mock"
for tool in terraform kubectl az; do
  ln -s "$TEMP_DIR/mock" "$TEMP_DIR/$tool"
done
export PATH="$TEMP_DIR:$PATH"

bash "$DEMO_DIR/generate-data.sh" --help >/dev/null
[[ ! -e "$MOCK_LOG" ]]
for args in "--rounds 0" "--rounds 1001" "--rounds 01" "--interval -1" "--interval 61" "--rounds" "--unknown" "--rounds 1000 --interval 60"; do
  read -r -a arguments <<< "$args"
  if bash "$DEMO_DIR/generate-data.sh" "${arguments[@]}" > "$TEMP_DIR/output" 2>&1; then
    echo "FAIL: accepted invalid arguments: $args" >&2
    exit 1
  fi
done
[[ ! -e "$MOCK_LOG" ]]

MAX_ATTEMPTS=1 bash "$DEMO_DIR/test-scenarios.sh" --rounds 3 --interval 0 --verify > "$TEMP_DIR/output"
[[ "$(grep -c 'kubectl -n aks-dcr-demo get configmap dcr-keep-' "$MOCK_LOG")" == 3 ]]
[[ "$(grep -c 'kubectl -n aks-dcr-demo get configmap dcr-drop-' "$MOCK_LOG")" == 3 ]]
grep -q 'create role dcr-payload-' "$MOCK_LOG"
grep -q 'PASS: retained reads/writes' "$TEMP_DIR/output"
grep -q 'EXPECTED_READS=3' "$TEMP_DIR/output"
grep -qx 'leave unchanged' "$MOCK_DEFAULT_KUBECONFIG"
config_path="$(sed -n 's/.*--file \([^ ]*\) --output none/\1/p' "$MOCK_LOG")"
[[ -n "$config_path" && ! -e "${config_path%/*}" ]]

if TRANSFORMED_DROP_READS=1 MAX_ATTEMPTS=1 bash "$DEMO_DIR/generate-data.sh" \
  --rounds 3 --interval 0 --verify > "$TEMP_DIR/output" 2>&1; then
  echo "FAIL: verification accepted an unfiltered marked GET." >&2
  exit 1
fi
grep -q 'FAIL: expected records' "$TEMP_DIR/output"

: > "$MOCK_LOG"
if FAIL_NAMESPACE=true bash "$DEMO_DIR/generate-data.sh" --interval 0 > "$TEMP_DIR/output" 2>&1; then
  echo "FAIL: reused an existing namespace." >&2
  exit 1
fi
if grep -q 'delete namespace' "$MOCK_LOG"; then
  echo "FAIL: tried deleting a namespace it did not create." >&2
  exit 1
fi
echo "PASS: generator arguments, paired reads, verification success/failure, isolated kubeconfig, and namespace safety."
