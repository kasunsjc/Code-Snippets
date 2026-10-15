#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/common.sh"

if [[ "${1:-}" == "--help" && $# == 1 ]]; then
  echo "Usage: bash deploy.sh (reads terraform/terraform.tfvars and GitHub auth environment variables)"
  exit 0
fi
[[ $# == 0 ]] || fail "Unknown argument. Use --help."
require_tools az terraform kubectl kubelogin helm
[[ -f "$TF_DIR/terraform.tfvars" ]] || fail "Copy terraform.tfvars.example to terraform.tfvars and review its settings."
validate_github_config
select_subscription

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" validate
terraform -chdir="$TF_DIR" plan -input=false -out=demo.tfplan
read -r -p "Apply this plan and create billable Azure resources? Type yes: " confirmation
[[ "$confirmation" == "yes" ]] || { echo "Deployment cancelled."; exit 0; }
terraform -chdir="$TF_DIR" apply -input=false demo.tfplan
rm -f "$TF_DIR/demo.tfplan"

bash "$DEMO_DIR/scripts/install-arc.sh"
printf 'AKS portal: %s\n' "$(tf_output portal_url)"
