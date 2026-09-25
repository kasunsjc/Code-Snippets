#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
DNS_RECORD_IP_FILE="$SCRIPT_DIR/.rendered/bookinfo-gateway-ip"

echo -e "${YELLOW}==========================================${NC}"
echo -e "${YELLOW}AKS Istio Service Mesh Add-on Demo - Cleanup${NC}"
echo -e "${YELLOW}==========================================${NC}"
echo ""

read -r -p "This will destroy all Azure resources created by this demo. Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

if [ -d "$TF_DIR" ] && { [ -f "$TF_DIR/terraform.tfstate" ] || [ -f "$TF_DIR/terraform.tfstate.backup" ] || [ -d "$TF_DIR/.terraform" ]; }; then
    echo -e "${YELLOW}Initializing Terraform for cleanup...${NC}"
    terraform -chdir="$TF_DIR" init -input=false >/dev/null

    # Capture everything we need for post-destroy cleanup up front - once the
    # cluster/DNS zone data source's dependent resources are destroyed, the
    # outputs that reference them can no longer be read from state.
    CLUSTER_NAME=$(terraform -chdir="$TF_DIR" output -raw aks_cluster_name 2>/dev/null || true)
    RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw resource_group_name 2>/dev/null || true)
    DNS_ZONE_NAME=$(terraform -chdir="$TF_DIR" output -raw dns_zone_name 2>/dev/null || true)
    DNS_ZONE_RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw dns_zone_resource_group 2>/dev/null || true)
    BOOKINFO_SUBDOMAIN=$(terraform -chdir="$TF_DIR" output -raw bookinfo_subdomain 2>/dev/null || true)
    BOOKINFO_GATEWAY_IP=$(tr -d '[:space:]' < "$DNS_RECORD_IP_FILE" 2>/dev/null || true)
    if [ -n "$DNS_ZONE_NAME" ] && [ -n "$DNS_ZONE_RESOURCE_GROUP" ] && [ -n "$BOOKINFO_SUBDOMAIN" ] && [ -n "$BOOKINFO_GATEWAY_IP" ]; then
        echo -e "${YELLOW}Removing the demo-managed bookinfo A record from Azure DNS...${NC}"
        az network dns record-set a remove-record \
            --resource-group "$DNS_ZONE_RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" \
            --record-set-name "$BOOKINFO_SUBDOMAIN" --ipv4-address "$BOOKINFO_GATEWAY_IP" \
            --only-show-errors >/dev/null 2>&1 || true

        REMAINING_A_RECORDS=$(az network dns record-set a show \
            --resource-group "$DNS_ZONE_RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" \
            --name "$BOOKINFO_SUBDOMAIN" --query 'length(arecords)' -o tsv 2>/dev/null || echo "")

        if [ "$REMAINING_A_RECORDS" = "0" ]; then
            az network dns record-set a delete \
                --resource-group "$DNS_ZONE_RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" \
                --name "$BOOKINFO_SUBDOMAIN" --yes --only-show-errors >/dev/null 2>&1 || true
            echo -e "${GREEN}✓ Demo A record removed and empty record set deleted${NC}"
        else
            echo -e "${GREEN}✓ Demo A record removed (or already gone)${NC}"
        fi
        echo ""
    elif [ -n "$DNS_ZONE_NAME" ] && [ -n "$DNS_ZONE_RESOURCE_GROUP" ] && [ -n "$BOOKINFO_SUBDOMAIN" ]; then
        echo -e "${YELLOW}Skipping Azure DNS record cleanup because no tracked demo gateway IP was found.${NC}"
        echo ""
    fi

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

echo -e "${YELLOW}Removing rendered manifest cache...${NC}"
rm -rf "$SCRIPT_DIR/.rendered"
echo -e "${GREEN}✓ .rendered/ removed${NC}"
echo ""

if [ -n "${CLUSTER_NAME:-}" ] && command -v kubectl &>/dev/null; then
    echo -e "${YELLOW}Removing the '$CLUSTER_NAME' entry from your local kubeconfig...${NC}"
    USER_ENTRY_NAME="clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}"
    kubectl config delete-context "$CLUSTER_NAME" &>/dev/null || true
    kubectl config delete-cluster "$CLUSTER_NAME" &>/dev/null || true
    kubectl config unset "users.$USER_ENTRY_NAME" &>/dev/null || true
    echo -e "${GREEN}✓ kubeconfig entries removed (or already gone)${NC}"
    echo ""
fi

echo -e "${GREEN}Cleanup complete.${NC}"
