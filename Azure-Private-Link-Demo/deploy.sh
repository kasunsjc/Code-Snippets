#!/bin/bash
# =============================================================================
# Deploy Azure Private Link Service + Private Endpoint demo
# =============================================================================
set -euo pipefail

# Colors
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}INFO:${NC} $1"; }
ok()    { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}WARN:${NC} $1"; }
fail()  { echo -e "${RED}ERROR:${NC} $1"; exit 1; }

# Variables (override via env)
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-rg-private-link-demo}"
LOCATION="${LOCATION:-northeurope}"
DEPLOYMENT_NAME="plk-demo-$(date +%Y%m%d-%H%M%S)"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"

# Pre-flight
command -v az >/dev/null || fail "Azure CLI not installed."
az account show >/dev/null 2>&1 || fail "Not logged in. Run 'az login' first."

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    warn "SSH public key not found at $SSH_KEY_PATH"
    read -rp "Generate a new SSH key pair now? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || fail "Provide an SSH public key via SSH_KEY_PATH env var."
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH%.pub}" -N "" -C "private-link-demo"
fi

export SSH_PUBLIC_KEY="$(cat "$SSH_KEY_PATH")"

ok "Subscription: $(az account show --query name -o tsv)"
ok "Resource group: $RESOURCE_GROUP_NAME (region: $LOCATION)"

# Resource group
if ! az group show -n "$RESOURCE_GROUP_NAME" >/dev/null 2>&1; then
    info "Creating resource group..."
    az group create -n "$RESOURCE_GROUP_NAME" -l "$LOCATION" -o none
fi

# Deploy
ok "Deploying Bicep template (this takes 5-8 minutes)..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$DEPLOYMENT_NAME" \
    --template-file main.bicep \
    --parameters main.bicepparam \
    --parameters location="$LOCATION" \
    -o none

# Outputs
ok "Deployment complete. Capturing outputs..."
OUTPUTS=$(az deployment group show -g "$RESOURCE_GROUP_NAME" -n "$DEPLOYMENT_NAME" --query properties.outputs -o json)

JUMP_IP=$(echo "$OUTPUTS"   | jq -r '.consumerJumpboxPublicIp.value')
PE_NAME=$(echo "$OUTPUTS"   | jq -r '.consumerPrivateEndpointName.value')
LB_FE_IP=$(echo "$OUTPUTS"  | jq -r '.providerLoadBalancerFrontendIp.value')
PLS_ALIAS=$(echo "$OUTPUTS" | jq -r '.privateLinkServiceAlias.value')
ST_NAME=$(echo "$OUTPUTS"   | jq -r '.storageAccountName.value')
ST_FQDN=$(echo "$OUTPUTS"   | jq -r '.storagePrivateEndpointFqdn.value')

# Private Endpoint NIC name + IP are assigned by Azure post-creation, look them up.
PE_NIC_ID=$(az network private-endpoint show -g "$RESOURCE_GROUP_NAME" -n "$PE_NAME" \
    --query 'networkInterfaces[0].id' -o tsv)
PE_NIC_IP=$(az network nic show --ids "$PE_NIC_ID" \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

# Create / refresh the A record in the custom Private DNS zone so the
# friendly hostname (provider.internal) resolves to the PE NIC IP.
DNS_ZONE=$(echo "$OUTPUTS"  | jq -r '.providerDnsZoneName.value')
DNS_HOST=$(echo "$OUTPUTS"  | jq -r '.providerHostname.value')
PROV_FQDN=$(echo "$OUTPUTS" | jq -r '.providerFqdn.value')

info "Upserting A record: $PROV_FQDN -> $PE_NIC_IP"
az network private-dns record-set a delete \
    -g "$RESOURCE_GROUP_NAME" -z "$DNS_ZONE" -n "$DNS_HOST" --yes >/dev/null 2>&1 || true
az network private-dns record-set a create \
    -g "$RESOURCE_GROUP_NAME" -z "$DNS_ZONE" -n "$DNS_HOST" --ttl 60 -o none
az network private-dns record-set a add-record \
    -g "$RESOURCE_GROUP_NAME" -z "$DNS_ZONE" -n "$DNS_HOST" --ipv4-address "$PE_NIC_IP" -o none

cat <<EOF

${GREEN}========================================================================
  Azure Private Link demo deployed successfully
========================================================================${NC}

Resource group:           $RESOURCE_GROUP_NAME

[Provider side]
  Internal LB frontend:   $LB_FE_IP        (only reachable inside provider VNet)
  Private Link Service:   $PLS_ALIAS

[Consumer side]
  Jumpbox public IP:      $JUMP_IP
  Private Endpoint IP:    $PE_NIC_IP        (lives in consumer VNet)
  Friendly FQDN:          $PROV_FQDN  (custom Private DNS zone)

[Storage PaaS scenario]
  Storage account:        $ST_NAME
  Private FQDN:           $ST_FQDN

------------------------------------------------------------------------
  Hands-on next steps
------------------------------------------------------------------------
1. SSH into the consumer jumpbox:
     ssh azureuser@$JUMP_IP

2. From the jumpbox, hit the provider service through the Private Endpoint:
     curl http://$PE_NIC_IP                     # by IP
     curl http://$PROV_FQDN                     # by friendly FQDN (Private DNS)
     for i in {1..6}; do curl -s http://$PROV_FQDN; done    # see load balancing

     # Verify DNS resolution from inside the consumer VNet:
     dig +short $PROV_FQDN                      # -> $PE_NIC_IP

3. Verify storage FQDN now resolves to a PRIVATE IP (Private DNS zone):
     dig +short $ST_FQDN
     # should return a 10.20.2.x address, NOT a public one.

4. Confirm there is NO peering between the two VNets:
     az network vnet peering list -g $RESOURCE_GROUP_NAME --vnet-name ${ST_NAME%st*}-provider-vnet -o table
     az network vnet peering list -g $RESOURCE_GROUP_NAME --vnet-name ${ST_NAME%st*}-consumer-vnet -o table

5. Inspect Private Endpoint approval state:
     az network private-endpoint-connection list \\
        --id \$(az network private-link-service show -g $RESOURCE_GROUP_NAME \\
                  -n ${ST_NAME%st*}-pls --query id -o tsv) -o table

To tear everything down: ./cleanup.sh
EOF
