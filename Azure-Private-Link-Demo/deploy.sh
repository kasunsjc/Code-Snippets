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
ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
PASSWORD_FILE="${PASSWORD_FILE:-./.vm-password}"

# Pre-flight
command -v az >/dev/null || fail "Azure CLI not installed."
az account show >/dev/null 2>&1 || fail "Not logged in. Run 'az login' first."

# -----------------------------------------------------------------------------
# Generate (or reuse) an Azure-compliant VM password.
#
# Azure Linux VM password rules:
#   - 12 to 72 characters
#   - Must satisfy 3 of 4: lowercase, uppercase, digit, special character
#   - Must NOT contain the username, or any of these reserved strings:
#     abc@123, P@$$w0rd, P@ssw0rd, P@ssword123, Pa$$word, pass@word1,
#     Password!, Password1, Password22, iloveyou!
#
# We deterministically build a 20-char password that always satisfies all four
# character classes, using openssl for the random body.
# -----------------------------------------------------------------------------
generate_password() {
    local rand specials body
    # 14 chars of url-safe base64 -> guaranteed mix of upper/lower/digit
    rand=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 14)
    # Pick 2 special chars from a safe set (no shell-meta hassles).
    specials='!@#%&*-_=+'
    local s1=${specials:$((RANDOM % ${#specials})):1}
    local s2=${specials:$((RANDOM % ${#specials})):1}
    # Compose: ensure at least one of each class by prefixing fixed anchors.
    body="Pl${s1}${rand}${s2}9"
    echo "$body"
}

if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
    info "Using ADMIN_PASSWORD from environment."
elif [[ -f "$PASSWORD_FILE" ]]; then
    ADMIN_PASSWORD=$(<"$PASSWORD_FILE")
    info "Reusing password from $PASSWORD_FILE"
else
    ADMIN_PASSWORD=$(generate_password)
    umask 077
    echo -n "$ADMIN_PASSWORD" > "$PASSWORD_FILE"
    ok "Generated new VM password and stored it at $PASSWORD_FILE (chmod 600)."
fi
export ADMIN_PASSWORD

# Sanity check: length 12-72.
len=${#ADMIN_PASSWORD}
if (( len < 12 || len > 72 )); then
    fail "ADMIN_PASSWORD length ($len) is outside Azure's 12-72 range."
fi

ok "Subscription: $(az account show --query name -o tsv)"
ok "Resource group: $RESOURCE_GROUP_NAME (region: $LOCATION)"

# Detect the caller's public IP so we can lock down the jumpbox NSG to it.
# Override by exporting ALLOWED_SSH_SOURCE_IP (e.g. "203.0.113.0/24" or "Internet").
if [[ -z "${ALLOWED_SSH_SOURCE_IP:-}" ]]; then
    MY_IP=$(curl -s --max-time 5 https://api.ipify.org || true)
    if [[ -n "$MY_IP" ]]; then
        ALLOWED_SSH_SOURCE_IP="${MY_IP}/32"
        info "Detected public IP: $MY_IP — locking jumpbox SSH to $ALLOWED_SSH_SOURCE_IP"
    else
        ALLOWED_SSH_SOURCE_IP="Internet"
        warn "Could not detect public IP; falling back to 'Internet' (NOT recommended)."
    fi
fi

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
    --parameters allowedSshSourceIp="$ALLOWED_SSH_SOURCE_IP" \
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

[VM credentials]
  Username:               $ADMIN_USERNAME
  Password:               $ADMIN_PASSWORD
  (also saved to:         $PASSWORD_FILE)

------------------------------------------------------------------------
  Hands-on next steps
------------------------------------------------------------------------
1. SSH into the consumer jumpbox (password auth):
     ssh $ADMIN_USERNAME@$JUMP_IP
     # paste the password above when prompted
     # (or: sshpass -p "\$(cat $PASSWORD_FILE)" ssh $ADMIN_USERNAME@$JUMP_IP)

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
