#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}AKS Istio Gateway API Demo - Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

#############################################
# CONFIGURATION SECTION
# Must match the values used during deploy.sh
#############################################
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-istio-gateway-demo}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-istio-gateway-demo}"
NODE_RESOURCE_GROUP="${NODE_RESOURCE_GROUP:-rg-aks-istio-gateway-demo-nodes}"
DOMAIN_NAME="${DOMAIN_NAME:-demo.example.com}"

# DNS Configuration (Optional - only needed if DNS records were created during deploy)
DNS_ZONE_NAME="${DNS_ZONE_NAME:-$DOMAIN_NAME}"   # Azure DNS zone name
DNS_ZONE_RG="${DNS_ZONE_RG:-}"                   # Resource group of the DNS zone (auto-detected if empty)
#############################################

echo -e "${YELLOW}Resource Group to be deleted: $RESOURCE_GROUP${NC}"
echo -e "${YELLOW}Node Resource Group: $NODE_RESOURCE_GROUP${NC}"
echo -e "${YELLOW}Domain: $DOMAIN_NAME${NC}"
echo ""
echo -e "${RED}WARNING: This will delete all resources in the resource group!${NC}"
echo "This includes:"
echo "  - AKS Cluster: $CLUSTER_NAME"
echo "  - AKS Node Resource Group: $NODE_RESOURCE_GROUP (VMs, disks, NICs, NSG, etc.)"
echo "  - Key Vault and SSL certificates"
echo "  - Virtual Network"
echo "  - DNS A records for $DOMAIN_NAME (if Azure DNS zone is found)"
echo "  - All associated resources"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Delete Kubernetes resources first (optional, as cluster will be deleted anyway)
echo -e "${YELLOW}Deleting Kubernetes resources...${NC}"
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    MANIFESTS_DIR="$SCRIPT_DIR/kubernetes-manifests"
    
    kubectl delete -f "$MANIFESTS_DIR/" --ignore-not-found=true || true
    echo -e "${GREEN}✓ Kubernetes resources deleted${NC}"
else
    echo -e "${YELLOW}Skipping Kubernetes resource cleanup (no access to cluster)${NC}"
fi
echo ""

# Clean up kubectl context
CLUSTER_NAME="${CLUSTER_NAME:-aks-istio-gateway-demo}"
echo -e "${YELLOW}Cleaning up kubectl context...${NC}"
CONTEXT_NAME=$(kubectl config get-contexts -o name | grep "$CLUSTER_NAME" || true)
if [[ -n "$CONTEXT_NAME" ]]; then
    kubectl config delete-context "$CONTEXT_NAME" || true
    echo -e "${GREEN}✓ Kubectl context removed: $CONTEXT_NAME${NC}"
else
    echo -e "${YELLOW}No kubectl context found for cluster: $CLUSTER_NAME${NC}"
fi
echo ""

# Remove DNS A records from Azure DNS zone
echo -e "${YELLOW}Checking for Azure DNS records to remove...${NC}"

DNS_ZONE_FOUND=false

# Auto-detect DNS zone resource group if not specified
if [ -z "$DNS_ZONE_RG" ]; then
    DETECTED_DNS_RG=$(az network dns zone list \
        --query "[?name=='$DNS_ZONE_NAME'].resourceGroup" \
        -o tsv 2>/dev/null | head -1)
    if [ -n "$DETECTED_DNS_RG" ]; then
        DNS_ZONE_RG="$DETECTED_DNS_RG"
        DNS_ZONE_FOUND=true
        echo -e "${GREEN}✓ Auto-detected DNS zone '$DNS_ZONE_NAME' in resource group '$DNS_ZONE_RG'${NC}"
    fi
else
    if az network dns zone show \
            --resource-group "$DNS_ZONE_RG" \
            --name "$DNS_ZONE_NAME" &>/dev/null; then
        DNS_ZONE_FOUND=true
        echo -e "${GREEN}✓ Found DNS zone '$DNS_ZONE_NAME' in resource group '$DNS_ZONE_RG'${NC}"
    else
        echo -e "${YELLOW}DNS zone '$DNS_ZONE_NAME' not found in resource group '$DNS_ZONE_RG' — skipping${NC}"
    fi
fi

if [ "$DNS_ZONE_FOUND" = "true" ]; then
    echo -e "${YELLOW}Removing DNS A records from zone '$DNS_ZONE_NAME'...${NC}"
    for RECORD in "httpbin" "echo" "echo-headers" "app"; do
        if az network dns record-set a show \
                --resource-group "$DNS_ZONE_RG" \
                --zone-name "$DNS_ZONE_NAME" \
                --name "$RECORD" &>/dev/null; then
            az network dns record-set a delete \
                --resource-group "$DNS_ZONE_RG" \
                --zone-name "$DNS_ZONE_NAME" \
                --name "$RECORD" \
                --yes \
                --output none
            echo -e "${GREEN}  ✓ Removed: $RECORD.$DNS_ZONE_NAME${NC}"
        else
            echo -e "${YELLOW}  - Skipping: $RECORD.$DNS_ZONE_NAME (not found)${NC}"
        fi
    done
    echo -e "${GREEN}✓ DNS records cleaned up${NC}"
else
    echo -e "${YELLOW}No Azure DNS zone found — no DNS records to remove${NC}"
fi
echo ""

# Delete resource group
echo -e "${YELLOW}Deleting resource group and all resources...${NC}"
az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Initiated!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Resource group deletion has been started in the background."
echo "You can check the status in the Azure Portal or with:"
echo "  az group show --name $RESOURCE_GROUP"
echo ""
