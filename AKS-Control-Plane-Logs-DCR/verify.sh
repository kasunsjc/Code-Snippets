#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
RUN_ID="${1:-}"
if [[ ! "$RUN_ID" =~ ^[0-9]{14}-[0-9]+$ ]]; then
  echo "Usage: bash $0 <run-id printed by test-scenarios.sh>" >&2
  exit 1
fi
for tool in terraform az jq; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

BASELINE_ID="$(terraform -chdir="$TF_DIR" output -raw baseline_workspace_customer_id)"
TRANSFORMED_ID="$(terraform -chdir="$TF_DIR" output -raw transformed_workspace_customer_id)"
CLUSTER_ID="$(terraform -chdir="$TF_DIR" output -raw cluster_id)"
SUBSCRIPTION_ID="$(terraform -chdir="$TF_DIR" output -raw subscription_id)"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-40}"
POLL_SECONDS="${POLL_SECONDS:-30}"
if [[ ! "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ || ! "$POLL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "MAX_ATTEMPTS and POLL_SECONDS must be positive integers." >&2
  exit 1
fi

query_workspace() {
  local workspace_id="$1"
  local query="$2"
  az rest --method post --subscription "$SUBSCRIPTION_ID" \
    --url "https://api.loganalytics.azure.com/v1/workspaces/$workspace_id/query" \
    --resource "https://api.loganalytics.io" \
    --body "$(jq -n --arg query "$query" '{query: $query, timespan: "PT2H"}')" \
    --output json
}

AUDIT_QUERY="AKSAudit
| where _ResourceId =~ '$CLUSTER_ID'
| where RequestUri contains '$RUN_ID' or tostring(ObjectRef.name) contains '$RUN_ID'
| summarize
    KeepReads=countif(Verb =~ 'get' and RequestUri contains 'dcr-keep-'),
    DropReads=countif(Verb =~ 'get' and RequestUri contains 'dcr-drop-'),
    Creates=countif(Verb =~ 'create'),
    Patches=countif(Verb =~ 'patch'),
    Deletes=countif(Verb =~ 'delete'),
    Payloads=countif(isnotnull(RequestObject) or isnotnull(ResponseObject))"
CONTROL_QUERY="AKSControlPlane
| where _ResourceId =~ '$CLUSTER_ID'
| summarize Total=count(), Noisy=countif(Level in~ ('debug', 'trace'))"

for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
  baseline="$(query_workspace "$BASELINE_ID" "$AUDIT_QUERY")"
  transformed="$(query_workspace "$TRANSFORMED_ID" "$AUDIT_QUERY")"
  # A partial query result must never be mistaken for a passing negative test.
  jq -e 'has("error") | not' <<< "$baseline" >/dev/null
  jq -e 'has("error") | not' <<< "$transformed" >/dev/null
  echo "Attempt $attempt: audit counts [keep reads, drop reads, creates, patches, deletes, payloads]"
  jq -c '.tables[0].rows[0]' <<< "$baseline"
  jq -c '.tables[0].rows[0]' <<< "$transformed"

  if jq -e '.tables[0].rows[0] | .[0] >= 10 and .[1] >= 10 and .[2] >= 2 and .[3] >= 1 and .[4] >= 2 and .[5] > 0' \
    <<< "$baseline" >/dev/null &&
    jq -e '.tables[0].rows[0] | .[0] >= 10 and .[1] == 0 and .[2] >= 2 and .[3] >= 1 and .[4] >= 2 and .[5] == 0' \
      <<< "$transformed" >/dev/null; then
    baseline_control="$(query_workspace "$BASELINE_ID" "$CONTROL_QUERY")"
    transformed_control="$(query_workspace "$TRANSFORMED_ID" "$CONTROL_QUERY")"
    jq -e 'has("error") | not' <<< "$baseline_control" >/dev/null
    jq -e 'has("error") | not' <<< "$transformed_control" >/dev/null
    if jq -e '.tables[0].rows[0][0] > 0' <<< "$baseline_control" >/dev/null &&
      jq -e '.tables[0].rows[0] | .[0] > 0 and .[1] == 0' <<< "$transformed_control" >/dev/null; then
      echo "PASS: retained reads/writes, dropped marked reads, removed audit payloads, and received control plane logs."
      echo "Control plane [total, debug/trace] baseline / transformed:"
      jq -c '.tables[0].rows[0]' <<< "$baseline_control"
      jq -c '.tables[0].rows[0]' <<< "$transformed_control"
      echo "Debug/trace filtering is observational if the baseline contains no debug/trace events."
      exit 0
    fi
  fi
  if ((attempt < MAX_ATTEMPTS)); then
    sleep "$POLL_SECONDS"
  fi
done
echo "FAIL: expected records did not arrive or transformation assertions failed; see README troubleshooting." >&2
exit 1
