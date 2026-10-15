#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for tool in terraform az; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
az account show --output none
: "${ARM_SUBSCRIPTION_ID:?Export ARM_SUBSCRIPTION_ID for the target Azure subscription.}"

terraform -chdir="$SCRIPT_DIR/terraform" init -input=false
terraform -chdir="$SCRIPT_DIR/terraform" apply "$@"
echo "Resources deployed. Allow diagnostics to initialize, then run: bash $SCRIPT_DIR/test-scenarios.sh"
