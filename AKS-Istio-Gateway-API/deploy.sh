#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AKS Istio Gateway API Demo - Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

#############################################
# CONFIGURATION SECTION
# Set these via environment variables or edit the defaults below
# Example: export DOMAIN_NAME="yourdomain.com" && export RESOURCE_GROUP="my-rg" && ./deploy.sh
#############################################

# === Domain & SSL Configuration (IMPORTANT: Customize for your use case) ===
DOMAIN_NAME="${DOMAIN_NAME:-demo.example.com}"          # Your domain name (certificate will be for *.DOMAIN_NAME)
SSL_PFX_PATH="${SSL_PFX_PATH:-}"                        # Optional: Path to your PFX certificate (leave empty for self-signed)
SSL_PFX_PASSWORD="${SSL_PFX_PASSWORD:-}"                # Optional: PFX password (leave empty if no password)
CERT_NAME="${CERT_NAME:-gateway-tls-cert}"              # Certificate name in Key Vault

# === Azure Resource Configuration ===
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-istio-gateway-demo}"               # Main resource group name
NODE_RESOURCE_GROUP="${NODE_RESOURCE_GROUP:-rg-aks-istio-gateway-demo-nodes}"  # AKS-managed node resource group
LOCATION="${LOCATION:-eastus}"                          # Azure region
KEYVAULT_NAME="${KEYVAULT_NAME:-kv-aks-istio-675}"  # Key Vault name (must be globally unique)

# === AKS Cluster Configuration ===
CLUSTER_NAME="${CLUSTER_NAME:-aks-istio-gateway-demo}" # AKS cluster name
K8S_VERSION="${K8S_VERSION:-1.34}"                      # Kubernetes version
NODE_COUNT="${NODE_COUNT:-2}"                           # Initial node count
NODE_SIZE="${NODE_SIZE:-Standard_D4s_v5}"               # VM size for nodes

# === Network Configuration ===
VNET_NAME="${VNET_NAME:-vnet-aks-istio-demo}"           # Virtual network name
SUBNET_NAME="${SUBNET_NAME:-snet-aks}"                  # Subnet name for AKS

# === DNS Configuration (Optional) ===
# If you have an Azure DNS zone, the script will automatically create A records.
# Leave DNS_ZONE_RG empty to auto-detect the zone across the subscription.
DNS_ZONE_NAME="${DNS_ZONE_NAME:-$DOMAIN_NAME}"          # Azure DNS zone name (defaults to DOMAIN_NAME)
DNS_ZONE_RG="${DNS_ZONE_RG:-}"                          # Resource group containing the DNS zone (auto-detected if empty)

# End of Configuration Section
#############################################

echo -e "${BLUE}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Node Resource Group: $NODE_RESOURCE_GROUP"
echo "  Domain Name: $DOMAIN_NAME"
if [ -n "$SSL_PFX_PATH" ]; then
    echo "  SSL Certificate: Custom PFX (${SSL_PFX_PATH})"
else
    echo "  SSL Certificate: Self-signed (will be generated)"
fi
echo "  Location: $LOCATION"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Node Count: $NODE_COUNT"
echo "  Node Size: $NODE_SIZE"
echo "  Kubernetes Version: $K8S_VERSION"
echo "  Key Vault Name: $KEYVAULT_NAME"
echo "  Domain Name: $DOMAIN_NAME"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Please install kubectl from https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    echo -e "${RED}Error: openssl is not installed${NC}"
    echo "Please install openssl for SSL certificate generation"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Check Azure login
echo -e "${YELLOW}Checking Azure login status...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged into Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✓ Logged into Azure subscription: ${SUBSCRIPTION}${NC}"
echo ""

# Install/update AKS preview extension
echo -e "${YELLOW}Ensuring aks-preview CLI extension is installed...${NC}"
if az extension show --name aks-preview &> /dev/null; then
    echo "Updating aks-preview extension..."
    az extension update --name aks-preview
else
    echo "Installing aks-preview extension..."
    az extension add --name aks-preview
fi
echo -e "${GREEN}✓ aks-preview extension ready${NC}"
echo ""

# Register preview features
echo -e "${YELLOW}Registering required preview features...${NC}"
echo "Note: This may take several minutes if features are not already registered"

az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview" || true
az feature register --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview" || true

# Wait for features to be registered
echo -e "${YELLOW}Waiting for features to be registered...${NC}"
for feature in "ManagedGatewayAPIPreview" "AppRoutingIstioGatewayAPIPreview"; do
    echo -n "Checking $feature... "
    while true; do
        state=$(az feature show --namespace "Microsoft.ContainerService" --name "$feature" --query properties.state -o tsv 2>/dev/null || echo "NotFound")
        if [[ "$state" == "Registered" ]]; then
            echo -e "${GREEN}Registered${NC}"
            break
        elif [[ "$state" == "NotFound" ]]; then
            echo -e "${RED}Failed to register${NC}"
            exit 1
        else
            echo -n "."
            sleep 10
        fi
    done
done

# Re-register the provider
echo -e "${YELLOW}Re-registering Microsoft.ContainerService provider...${NC}"
az provider register --namespace Microsoft.ContainerService
echo ""

# Create Resource Group
echo -e "${YELLOW}Creating resource group...${NC}"
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${GREEN}✓ Resource group '$RESOURCE_GROUP' already exists — skipping${NC}"
else
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags "Environment=Demo" "Project=AKS-Istio-Gateway-API" "ManagedBy=AzureCLI"
    echo -e "${GREEN}✓ Resource group created${NC}"
fi
echo ""

# Create Virtual Network
echo -e "${YELLOW}Creating virtual network...${NC}"
if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ VNet '$VNET_NAME' already exists — skipping${NC}"
else
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix 10.0.0.0/16 \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefix 10.0.0.0/22
    echo -e "${GREEN}✓ Virtual network created${NC}"
fi

SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$SUBNET_NAME" \
    --query id -o tsv)
echo ""

# Create Azure Key Vault
echo -e "${YELLOW}Creating Azure Key Vault...${NC}"
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${GREEN}✓ Key Vault '$KEYVAULT_NAME' already exists — skipping${NC}"
else
    az keyvault create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$KEYVAULT_NAME" \
        --location "$LOCATION" \
        --enable-rbac-authorization true \
        --tags "Environment=Demo" "Project=AKS-Istio-Gateway-API"
    echo -e "${GREEN}✓ Key Vault created: $KEYVAULT_NAME${NC}"
fi

KEYVAULT_ID=$(az keyvault show \
    --name "$KEYVAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)
echo ""

# Prepare SSL certificate for import
if [ -n "$SSL_PFX_PATH" ]; then
    # User provided their own PFX certificate
    echo -e "${YELLOW}Using custom PFX certificate: $SSL_PFX_PATH${NC}"
    
    # Validate certificate file exists
    if [ ! -f "$SSL_PFX_PATH" ]; then
        echo -e "${RED}✗ Error: Certificate file not found: $SSL_PFX_PATH${NC}"
        exit 1
    fi
    
    CERT_FILE="$SSL_PFX_PATH"
    CERT_PASSWORD="$SSL_PFX_PASSWORD"
    echo -e "${GREEN}✓ Custom certificate validated${NC}"
else
    # Generate self-signed SSL certificate
    echo -e "${YELLOW}Generating self-signed SSL certificate for domain: $DOMAIN_NAME${NC}"
    CERT_DIR=$(mktemp -d)
    trap "rm -rf $CERT_DIR" EXIT

    # Create OpenSSL config for SAN (Subject Alternative Names)
    cat > "$CERT_DIR/openssl.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=WA
L=Seattle
O=Demo Organization
OU=IT
CN=$DOMAIN_NAME

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN_NAME
DNS.2 = *.$DOMAIN_NAME
DNS.3 = httpbin.$DOMAIN_NAME
DNS.4 = echo.$DOMAIN_NAME
DNS.5 = echo-headers.$DOMAIN_NAME
DNS.6 = app.$DOMAIN_NAME
EOF

# Generate private key and certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERT_DIR/tls.key" \
    -out "$CERT_DIR/tls.crt" \
    -config "$CERT_DIR/openssl.cnf" \
    -extensions v3_req

    # Convert to PFX format for Key Vault
    openssl pkcs12 -export \
        -in "$CERT_DIR/tls.crt" \
        -inkey "$CERT_DIR/tls.key" \
        -out "$CERT_DIR/certificate.pfx" \
        -password pass:

    CERT_FILE="$CERT_DIR/certificate.pfx"
    CERT_PASSWORD=""
    echo -e "${GREEN}✓ Self-signed SSL certificate generated${NC}"
fi
echo ""

# Get current user's object ID for Key Vault RBAC
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign Key Vault Secrets Officer role to current user (to import certificate)
echo -e "${YELLOW}Assigning Key Vault permissions...${NC}"
if az role assignment list --role "Key Vault Certificates Officer" --assignee "$USER_OBJECT_ID" --scope "$KEYVAULT_ID" --query '[0].id' -o tsv 2>/dev/null | grep -q .; then
    echo -e "${GREEN}✓ Key Vault Certificates Officer role already assigned — skipping${NC}"
else
    az role assignment create \
        --role "Key Vault Certificates Officer" \
        --assignee "$USER_OBJECT_ID" \
        --scope "$KEYVAULT_ID" \
        --output none
    # Wait a bit for RBAC propagation
    sleep 10
fi

# Import certificate to Key Vault
echo -e "${YELLOW}Importing certificate to Key Vault...${NC}"
if az keyvault certificate show --vault-name "$KEYVAULT_NAME" --name "$CERT_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ Certificate '$CERT_NAME' already exists in Key Vault — skipping${NC}"
else
    az keyvault certificate import \
        --vault-name "$KEYVAULT_NAME" \
        --name "$CERT_NAME" \
        --file "$CERT_FILE" \
        --password "$CERT_PASSWORD"
    echo -e "${GREEN}✓ Certificate imported to Key Vault${NC}"
fi
echo ""

# Create AKS Cluster with Gateway API and App Routing (Istio)
echo -e "${YELLOW}Creating AKS cluster with Gateway API and Istio app routing...${NC}"
if az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ AKS cluster '$CLUSTER_NAME' already exists — skipping create${NC}"
else
    echo "This may take 10-15 minutes..."
    az aks create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --location "$LOCATION" \
        --node-resource-group "$NODE_RESOURCE_GROUP" \
        --kubernetes-version "$K8S_VERSION" \
        --node-count "$NODE_COUNT" \
        --node-vm-size "$NODE_SIZE" \
        --network-plugin azure \
        --vnet-subnet-id "$SUBNET_ID" \
        --service-cidr 10.1.0.0/16 \
        --dns-service-ip 10.1.0.10 \
        --enable-managed-identity \
        --enable-gateway-api \
        --enable-app-routing-istio \
        --enable-addons azure-keyvault-secrets-provider \
        --enable-secret-rotation \
        --rotation-poll-interval 2m \
        --tier standard \
        --node-osdisk-type Managed \
        --enable-cluster-autoscaler \
        --min-count 1 \
        --max-count 3 \
        --tags "Environment=Demo" "Project=AKS-Istio-Gateway-API"
    echo -e "${GREEN}✓ AKS cluster created successfully${NC}"
fi
echo ""

# Get AKS credentials
echo -e "${YELLOW}Getting AKS credentials...${NC}"
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

echo -e "${GREEN}✓ Credentials configured${NC}"
echo ""

# Configure Key Vault RBAC for AKS Secrets Provider
echo -e "${YELLOW}Configuring Key Vault access for AKS...${NC}"

# Get the Secrets Provider managed identity client ID
SECRETS_PROVIDER_IDENTITY=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)

# Get the managed identity object ID
SECRETS_PROVIDER_OBJECT_ID=$(az ad sp show \
    --id "$SECRETS_PROVIDER_IDENTITY" \
    --query id -o tsv)

# Assign Key Vault Secrets User role to read secrets
if az role assignment list --role "Key Vault Secrets User" --assignee-object-id "$SECRETS_PROVIDER_OBJECT_ID" --scope "$KEYVAULT_ID" --query '[0].id' -o tsv 2>/dev/null | grep -q .; then
    echo -e "${GREEN}✓ Key Vault Secrets User role already assigned — skipping${NC}"
else
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee-object-id "$SECRETS_PROVIDER_OBJECT_ID" \
        --assignee-principal-type ServicePrincipal \
        --scope "$KEYVAULT_ID" \
        --output none
fi

# Assign Key Vault Certificate User role to read certificates
if az role assignment list --role "Key Vault Certificate User" --assignee-object-id "$SECRETS_PROVIDER_OBJECT_ID" --scope "$KEYVAULT_ID" --query '[0].id' -o tsv 2>/dev/null | grep -q .; then
    echo -e "${GREEN}✓ Key Vault Certificate User role already assigned — skipping${NC}"
else
    az role assignment create \
        --role "Key Vault Certificate User" \
        --assignee-object-id "$SECRETS_PROVIDER_OBJECT_ID" \
        --assignee-principal-type ServicePrincipal \
        --scope "$KEYVAULT_ID" \
        --output none
fi

echo -e "${GREEN}✓ Key Vault access configured${NC}"
echo ""

# Create SecretProviderClass for TLS certificate
echo -e "${YELLOW}Creating SecretProviderClass for TLS certificate...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: gateway-tls-cert-spc
  namespace: default
spec:
  provider: azure
  secretObjects:
  - secretName: gateway-tls-secret
    type: kubernetes.io/tls
    data:
    - objectName: gateway-tls-key   # matches objectAlias below — private key
      key: tls.key
    - objectName: gateway-tls-crt   # matches objectAlias below — certificate
      key: tls.crt
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "$SECRETS_PROVIDER_IDENTITY"
    keyvaultName: "$KEYVAULT_NAME"
    cloudName: "AzurePublicCloud"
    objects: |
      array:
        - |
          objectName: $CERT_NAME
          objectType: secret
          objectAlias: "gateway-tls-key"
        - |
          objectName: $CERT_NAME
          objectType: cert
          objectAlias: "gateway-tls-crt"
    tenantId: "$(az account show --query tenantId -o tsv)"
EOF

echo -e "${GREEN}✓ SecretProviderClass created${NC}"
echo ""

# Wait for istiod to be ready
echo -e "${YELLOW}Waiting for Istio control plane to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=istiod -n aks-istio-system --timeout=300s
echo -e "${GREEN}✓ Istio control plane is ready${NC}"
echo ""

# Verify GatewayClass exists
echo -e "${YELLOW}Verifying Gateway API resources...${NC}"
kubectl get gatewayclass approuting-istio
echo ""

# Deploy sample applications
echo -e "${YELLOW}Deploying sample applications...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/kubernetes-manifests"

echo "Deploying httpbin application..."
kubectl apply -f "$MANIFESTS_DIR/01-httpbin-app.yaml"

echo "Deploying Gateway and HTTPRoute for httpbin (domain: httpbin.$DOMAIN_NAME)..."
sed "s/__DOMAIN_NAME__/$DOMAIN_NAME/g" "$MANIFESTS_DIR/02-gateway-httproute.yaml" | kubectl apply -f -

echo "Deploying echo applications (v1 and v2)..."
kubectl apply -f "$MANIFESTS_DIR/03-echo-apps.yaml"

echo "Deploying advanced routing examples with domain: $DOMAIN_NAME..."
sed "s/__DOMAIN_NAME__/$DOMAIN_NAME/g" "$MANIFESTS_DIR/04-advanced-traffic-splitting.yaml" | kubectl apply -f -
sed "s/__DOMAIN_NAME__/$DOMAIN_NAME/g" "$MANIFESTS_DIR/05-header-based-routing.yaml" | kubectl apply -f -
sed "s/__DOMAIN_NAME__/$DOMAIN_NAME/g" "$MANIFESTS_DIR/06-path-based-routing.yaml" | kubectl apply -f -

echo ""
echo -e "${GREEN}✓ Sample applications deployed${NC}"
echo ""

# Wait for Gateway to be programmed
echo -e "${YELLOW}Waiting for Gateways to be programmed...${NC}"
kubectl wait --for=condition=programmed gateway/httpbin-gateway --timeout=300s
kubectl wait --for=condition=programmed gateway/echo-gateway --timeout=300s
echo ""

# Get Gateway IP addresses
echo -e "${YELLOW}Retrieving Gateway IP addresses...${NC}"
HTTPBIN_IP=$(kubectl get gateway httpbin-gateway -o jsonpath='{.status.addresses[0].value}')
ECHO_IP=$(kubectl get gateway echo-gateway -o jsonpath='{.status.addresses[0].value}')
# ─────────────────────────────────────────────
# DNS Configuration
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Configuring DNS records...${NC}"

DNS_ZONE_FOUND=false

# Auto-detect DNS zone resource group if not specified
if [ -z "$DNS_ZONE_RG" ]; then
    DETECTED_DNS_RG=$(az network dns zone list \
        --query "[?name=='$DNS_ZONE_NAME'].resourceGroup" \
        -o tsv 2>/dev/null | head -1)
    if [ -n "$DETECTED_DNS_RG" ]; then
        DNS_ZONE_RG="$DETECTED_DNS_RG"
        DNS_ZONE_FOUND=true
        echo -e "${GREEN}✓ Auto-detected Azure DNS zone '$DNS_ZONE_NAME' in resource group '$DNS_ZONE_RG'${NC}"
    fi
else
    # Verify the zone exists in the specified resource group
    if az network dns zone show \
            --resource-group "$DNS_ZONE_RG" \
            --name "$DNS_ZONE_NAME" &>/dev/null; then
        DNS_ZONE_FOUND=true
        echo -e "${GREEN}✓ Found Azure DNS zone '$DNS_ZONE_NAME' in resource group '$DNS_ZONE_RG'${NC}"
    else
        echo -e "${RED}✗ DNS zone '$DNS_ZONE_NAME' not found in resource group '$DNS_ZONE_RG'${NC}"
    fi
fi

if [ "$DNS_ZONE_FOUND" = "true" ]; then
    echo -e "${YELLOW}Creating/updating DNS A records in zone '$DNS_ZONE_NAME'...${NC}"

    # Helper: delete the existing record set (if any) then create fresh with one IP.
    # This prevents stale IPs accumulating across re-runs.
    upsert_dns_record() {
        local NAME="$1"
        local IP="$2"
        az network dns record-set a delete \
            --resource-group "$DNS_ZONE_RG" \
            --zone-name "$DNS_ZONE_NAME" \
            --name "$NAME" --yes --output none 2>/dev/null || true
        az network dns record-set a add-record \
            --resource-group "$DNS_ZONE_RG" \
            --zone-name "$DNS_ZONE_NAME" \
            --record-set-name "$NAME" \
            --ipv4-address "$IP" \
            --ttl 300 \
            --output none
    }

    # httpbin subdomain → httpbin-gateway IP
    upsert_dns_record "httpbin" "$HTTPBIN_IP"
    echo -e "${GREEN}  ✓ httpbin.$DNS_ZONE_NAME  →  $HTTPBIN_IP${NC}"

    # echo, echo-headers, app subdomains → echo-gateway IP
    for SUBDOMAIN in "echo" "echo-headers" "app"; do
        upsert_dns_record "$SUBDOMAIN" "$ECHO_IP"
        echo -e "${GREEN}  ✓ $SUBDOMAIN.$DNS_ZONE_NAME  →  $ECHO_IP${NC}"
    done

    echo -e "${GREEN}✓ All DNS records updated successfully${NC}"
else
    echo -e "${YELLOW}No Azure DNS zone found for '$DNS_ZONE_NAME'.${NC}"
    echo -e "${YELLOW}Add the following A records manually with your DNS provider:${NC}"
    echo ""
    echo -e "  ${BLUE}Hostname                              Type   Value${NC}"
    echo    "  ────────────────────────────────────────────────────────────────"
    printf  "  %-38s A      %s\n" "httpbin.$DOMAIN_NAME"       "$HTTPBIN_IP"
    printf  "  %-38s A      %s\n" "echo.$DOMAIN_NAME"          "$ECHO_IP"
    printf  "  %-38s A      %s\n" "echo-headers.$DOMAIN_NAME" "$ECHO_IP"
    printf  "  %-38s A      %s\n" "app.$DOMAIN_NAME"           "$ECHO_IP"
    echo ""
    echo    "  Or a single wildcard record (if your provider supports it):"
    printf  "  %-38s A      %s\n" "*.$DOMAIN_NAME" "$ECHO_IP"
    echo -e "  ${YELLOW}Note: A wildcard won't cover httpbin.$DOMAIN_NAME if it resolves to a different IP.${NC}"
    echo ""
    echo    "  To let this script manage DNS automatically, set:"
    echo    "    export DNS_ZONE_NAME='$DOMAIN_NAME'"
    echo    "    export DNS_ZONE_RG='<resource-group-containing-your-dns-zone>'"
    echo    "  Then re-run ./deploy.sh"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Cluster Information:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Subscription: $SUBSCRIPTION"
echo ""
echo -e "${YELLOW}Gateway Information:${NC}"
echo "  httpbin-gateway IP: $HTTPBIN_IP"
echo "  echo-gateway IP: $ECHO_IP"
echo ""
echo -e "${YELLOW}Test Commands:${NC}"
echo ""
echo "Set your domain for testing (if not already set in your shell):"
echo "   export DOMAIN_NAME='$DOMAIN_NAME'"
echo ""
echo "1. Test httpbin service:"
echo "   curl -k -s -H 'Host: httpbin.$DOMAIN_NAME' https://$HTTPBIN_IP/get | jq"
echo ""
echo "2. Test echo service (canary deployment - 90% v1, 10% v2):"
echo "   for i in {1..10}; do curl -k -s -H 'Host: echo.$DOMAIN_NAME' https://$ECHO_IP/ | grep -o 'Echo v[12]'; done"
echo ""
echo "3. Test header-based routing:"
echo "   # Routes to v1 (default)"
echo "   curl -k -s -H 'Host: echo-headers.$DOMAIN_NAME' https://$ECHO_IP/ | grep -o 'Echo v[12]'"
echo "   # Routes to v2 (with header)"
echo "   curl -k -s -H 'Host: echo-headers.$DOMAIN_NAME' -H 'version: v2' https://$ECHO_IP/ | grep -o 'Echo v[12]'"
echo ""
echo "4. Test path-based routing:"
echo "   curl -k -s -H 'Host: app.$DOMAIN_NAME' https://$ECHO_IP/v1/ | grep -o 'Echo v[12]'"
echo "   curl -k -s -H 'Host: app.$DOMAIN_NAME' https://$ECHO_IP/v2/ | grep -o 'Echo v[12]'"
echo ""
echo -e "${YELLOW}Explore the cluster:${NC}"
echo "  kubectl get pods -n aks-istio-system"
echo "  kubectl get gateway"
echo "  kubectl get httproute"
echo "  kubectl describe gateway httpbin-gateway"
echo ""
echo -e "${YELLOW}Azure Portal:${NC}"
echo "  https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/overview"
echo ""
