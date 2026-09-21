#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

echo -e "${YELLOW}==========================================${NC}"
echo -e "${YELLOW}AKS Istio Service Mesh Add-on Demo - Cleanup${NC}"
echo -e "${YELLOW}==========================================${NC}"
echo ""

read -r -p "This will destroy all Azure resources created by this demo. Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

if [ -d "$TF_DIR" ] && [ -f "$TF_DIR/.terraform.lock.hcl" ]; then
    echo -e "${YELLOW}Running terraform destroy...${NC}"
    terraform -chdir="$TF_DIR" destroy -auto-approve
    echo -e "${GREEN}✓ Azure resources destroyed${NC}"
else
    echo -e "${YELLOW}No Terraform state found - skipping destroy${NC}"
fi
echo ""

echo -e "${YELLOW}Removing local Terraform state and provider cache...${NC}"
rm -f "$TF_DIR"/terraform.tfstate "$TF_DIR"/terraform.tfstate.backup
rm -rf "$TF_DIR"/.terraform
echo -e "${GREEN}✓ Local Terraform files removed${NC}"
echo ""

echo -e "${GREEN}Cleanup complete.${NC}"
