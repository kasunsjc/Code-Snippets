# AKS Istio Gateway API Demo

This demo showcases the new **AKS App Routing with Istio-based Gateway API implementation** (preview), announced in March 2026. This feature brings modern, role-oriented traffic management to Azure Kubernetes Service without requiring a full Istio service mesh.

## 📋 Overview

The AKS app routing add-on now supports the Kubernetes Gateway API through a lightweight Istio control plane. This provides:

- **Envoy-based gateway infrastructure** - High-performance traffic routing
- **No sidecar injection** - Istio manages only the gateway, not your workloads
- **Gateway API standard** - Modern, role-oriented networking model
- **Automatic infrastructure** - AKS provisions LoadBalancer, HPA, and PDB for gateways
- **Advanced routing** - Traffic splitting, header-based routing, path-based routing
- **SSL/TLS Termination** - Integrated with Azure Key Vault for certificate management
- **Secure Secrets** - Key Vault Secrets Provider for secure certificate storage

### Why Gateway API?

The Kubernetes Ingress API has served well but has limitations:
- Minimal spec requiring vendor-specific annotations
- Flat model that doesn't separate platform and application concerns
- Limited support for modern routing patterns

Gateway API addresses these with a layered, role-oriented model:
- **GatewayClass** - Infrastructure type (managed by platform team)
- **Gateway** - Gateway instance (managed by cluster operators)
- **HTTPRoute/GRPCRoute** - Traffic rules (managed by app developers)

### Migration Path from Ingress-NGINX

The Ingress-NGINX project was retired in March 2026. Microsoft provides:
- Security patches until **November 2026**
- **This Gateway API implementation as the recommended migration path**

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Azure Key Vault                            │
│  ┌────────────────────────────────────────────────────┐      │
│  │  SSL/TLS Certificate (PFX)                          │      │
│  │  - Subject: *.demo.example.com                      │      │
│  │  - Type: Self-signed (or bring your own)            │      │
│  └────────────────┬───────────────────────────────────┘      │
└────────────────────┼──────────────────────────────────────────┘
                     │ Key Vault Secrets Provider CSI Driver
                     │ (Syncs to Kubernetes Secret)
                     ▼
┌──────────────────────────────────────────────────────────────┐
│              Kubernetes Secret: gateway-tls-secret            │
│                (type: kubernetes.io/tls)                      │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     │ Referenced by Gateway
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                     Azure Load Balancer                      │
│                  (External IP: Programmed)                   │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│              Gateway (approuting-istio)                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Envoy Pods (HPA: 2-5 replicas, PDB: min 1)         │  │
│  │  - Listener: HTTP (80)                               │  │
│  │  - Listener: HTTPS (443) with TLS Termination        │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────┬────────────────┬─────────────────────────────┘
              │                │
┌─────────────▼──────┐    ┌───▼──────────────────┐
│   HTTPRoute        │    │   HTTPRoute          │
│   (httpbin)        │    │   (echo-canary)      │
│   HTTPS listener   │    │   HTTPS listener     │
└─────────┬──────────┘    └───┬──────────────────┘
          │                   │
┌─────────▼──────────┐    ┌───▼──────┐  ┌────────┐
│  httpbin Service   │    │ echo-v1  │  │echo-v2 │
│     (port 8000)    │    │  (90%)   │  │ (10%)  │
└────────────────────┘    └──────────┘  └────────┘
```

## 🚀 Prerequisites

### Required Tools
- **Azure CLI** (`az`) version 2.60.0 or later - [Install](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **kubectl** >= 1.30 - [Install](https://kubernetes.io/docs/tasks/tools/)
- **OpenSSL** - For SSL certificate generation (usually pre-installed on macOS/Linux)
- **jq** (optional, for JSON parsing test outputs) - [Install](https://jqlang.github.io/jq/download/)
- Active Azure subscription with contributor access

### Domain Name Configuration

The demo generates a self-signed certificate for `demo.example.com` by default. **You should customize this** for your use case:

**Option 1: Environment Variable (Recommended)**
```bash
export DOMAIN_NAME="yourdomain.com"
./deploy.sh
```

**Option 2: Edit deploy.sh**

Update line ~24 in `deploy.sh`:
```bash
DOMAIN_NAME="${DOMAIN_NAME:-yourdomain.com}"  # <-- Change default here
```

The script will generate a wildcard certificate for:
- `*.DOMAIN_NAME` (e.g., `*.yourdomain.com`)
- `httpbin.DOMAIN_NAME` (e.g., `httpbin.yourdomain.com`)
- `echo.DOMAIN_NAME` (e.g., `echo.yourdomain.com`)
- And other subdomains used in the demo

### SSL Certificate Configuration

**Default Behavior**: The script generates a self-signed certificate automatically.

**Bring Your Own Certificate**: If you have a certificate from a Certificate Authority (CA), you can provide it:

```bash
# Provide your PFX certificate path and password (if any)
export SSL_PFX_PATH="/path/to/your/certificate.pfx"
export SSL_PFX_PASSWORD="your-certificate-password"  # Optional, leave empty if no password
export DOMAIN_NAME="yourdomain.com"  # Should match certificate domain

./deploy.sh
```

**Supported Certificate Formats**:
- **PFX/PKCS12** format (`.pfx` or `.p12` file)
- Must contain both the certificate and private key
- Optionally password-protected

**Converting from PEM to PFX** (if you have separate `.crt` and `.key` files):
```bash
openssl pkcs12 -export \
  -in certificate.crt \
  -inkey private.key \
  -out certificate.pfx \
  -password pass:YourPassword
```

**For Production**: Always use certificates from a trusted CA (Let's Encrypt, DigiCert, etc.) instead of self-signed certificates.

### Azure Preview Features

This demo uses preview features that must be registered:

```bash
# Register preview features (the deploy.sh script does this automatically)
az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"
az feature register --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview"

# Check registration status
az feature show --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"
az feature show --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview"

# Re-register provider after features are registered
az provider register --namespace Microsoft.ContainerService
```

### AKS Preview CLI Extension

```bash
# Install or update
az extension add --name aks-preview
az extension update --name aks-preview
```

## 📦 What's Included

### Infrastructure (Azure CLI)

The demo uses Azure CLI for deployment, providing the best support for these preview features.

**Provisioned Resources:**
- **AKS cluster** with Gateway API and App Routing (Istio) enabled
- **Custom node resource group** with readable name (not default MC_* format)
- **Azure Key Vault** for secure SSL certificate storage
- **Key Vault Secrets Provider** add-on enabled on AKS
- **SSL/TLS certificate** - Either custom PFX (if provided) or self-signed (auto-generated)
- **Virtual Network** with dedicated AKS subnet (10.0.0.0/16)
- **Managed identity** for AKS with Key Vault RBAC permissions
- **Auto-scaling** configured for system node pool (1-3 nodes)
- **Istio control plane** (meshless) via App Routing

### Kubernetes Resources

#### Sample Applications
1. **httpbin** - HTTP testing service
2. **echo-v1** - Echo service version 1
3. **echo-v2** - Echo service version 2

#### Gateway API Resources
1. **TLS Secret Sync Pod** - Syncs SSL certificate from Key Vault to Kubernetes
2. **SecretProviderClass** - Configures Key Vault integration for TLS certificates
3. **Gateways with HTTPS** - Both HTTP (80) and HTTPS (443) listeners
4. **Basic Gateway & HTTPRoute** - Simple path-based routing with SSL termination
5. **Traffic Splitting** - Canary deployment (90/10 split) over HTTPS
6. **Header-based Routing** - Route by HTTP headers over HTTPS
7. **Path-based Routing** - Multiple services on one gateway over HTTPS

## 🛠️ Deployment

### Quick Start (Automated)

```bash
# Navigate to the demo directory
cd AKS-Istio-Gateway-API

# Run the deployment script
./deploy.sh
```

The script will:
1. ✅ Check prerequisites (Azure CLI, kubectl, openssl)
2. ✅ Install/update aks-preview CLI extension
3. ✅ Register Azure preview features (if needed)
4. ✅ Create resource group and virtual network
5. ✅ **Create Azure Key Vault**
6. ✅ **Generate self-signed SSL certificate**
7. ✅ **Import certificate to Key Vault**
8. ✅ Deploy AKS cluster with Gateway API, Istio app routing, and Key Vault Secrets Provider
9. ✅ **Configure Key Vault RBAC for AKS**
10. ✅ **Create SecretProviderClass for TLS certificates**
11. ✅ Configure kubectl access
12. ✅ Deploy sample applications with HTTPS
13. ✅ Wait for Gateways to be ready
14. ✅ Display test commands and gateway IPs

### Configuration Variables

All deployment settings can be customized via environment variables. Set them before running the script:

```bash
#############################################
# CONFIGURATION VARIABLES
# Copy, customize, and paste this entire block to configure the deployment
#############################################

# === Domain & SSL Configuration (IMPORTANT: Customize for your use case) ===
export DOMAIN_NAME="yourdomain.com"              # Your domain (cert will be for *.yourdomain.com)
export SSL_PFX_PATH=""                            # Optional: /path/to/certificate.pfx (leave empty for self-signed)
export SSL_PFX_PASSWORD=""                        # Optional: Certificate password (leave empty if no password)
export CERT_NAME="gateway-tls-cert"              # Certificate name in Key Vault

# === Azure Resource Configuration ===
export RESOURCE_GROUP="rg-aks-istio-demo"        # Main resource group name
export NODE_RESOURCE_GROUP="rg-aks-istio-nodes"  # AKS-managed node resource group (VMs, disks, NICs)
export LOCATION="eastus"                          # Azure region (eastus, westus2, etc.)
export KEYVAULT_NAME="kv-aks-istio-demo"         # Key Vault name (must be globally unique, 3-24 chars)

# === AKS Cluster Configuration ===
export CLUSTER_NAME="aks-istio-demo"             # AKS cluster name
export K8S_VERSION="1.34"                         # Kubernetes version
export NODE_COUNT="2"                             # Initial node count (autoscales 1-3)
export NODE_SIZE="Standard_D4s_v5"               # VM size (Standard_D4s_v5, Standard_D8s_v5, etc.)

# === Network Configuration (Advanced - typically no need to change) ===
export VNET_NAME="vnet-aks-istio-demo"           # Virtual network name
export SUBNET_NAME="snet-aks"                     # Subnet name

# === DNS Configuration (Optional - for automatic A record creation) ===
# If set, the script will auto-create DNS A records in your Azure DNS zone.
# Leave DNS_ZONE_RG empty to let the script auto-detect the zone across the subscription.
export DNS_ZONE_NAME="mycompany.com"              # Azure DNS zone name (defaults to DOMAIN_NAME)
export DNS_ZONE_RG="rg-dns"                       # Resource group containing the DNS zone (auto-detected if empty)

# Run deployment
./deploy.sh
```

**Quick Start Examples:**

```bash
# Minimal configuration (with your domain)
export DOMAIN_NAME="mycompany.com"
./deploy.sh

# With Azure DNS (auto-create A records)
export DOMAIN_NAME="mycompany.com"
export DNS_ZONE_RG="rg-dns"        # script auto-creates httpbin/echo/echo-headers/app records
./deploy.sh

# With custom certificate
export DOMAIN_NAME="mycompany.com"
export SSL_PFX_PATH="/path/to/mycompany.pfx"
export SSL_PFX_PASSWORD="MySecurePassword"
./deploy.sh

# Custom Azure resources
export DOMAIN_NAME="mycompany.com"
export RESOURCE_GROUP="rg-production-aks"
export NODE_RESOURCE_GROUP="rg-production-aks-nodes"
export LOCATION="westus2"
export CLUSTER_NAME="aks-prod-cluster"
export NODE_COUNT="3"
export NODE_SIZE="Standard_D8s_v5"
./deploy.sh
```

**Important Notes:**
- **DOMAIN_NAME**: If not set, defaults to `demo.example.com` (placeholder - not routable)
- **SSL Certificate**: If `SSL_PFX_PATH` is empty, a self-signed certificate is generated automatically
- **Key Vault Name**: Must be globally unique across Azure (3-24 alphanumeric characters)
- **Node Resource Group**: Custom readable name instead of Azure's default `MC_*` format

### Manual Step-by-Step Deployment

If you prefer to run commands manually:

```bash
# 1. Install the aks-preview extension
az extension add --name aks-preview
az extension update --name aks-preview

# 2. Register preview features
az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"
az feature register --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview"

# 3. Wait for registration (check status)
az feature show --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"
az feature show --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview"

# 4. Re-register provider
az provider register --namespace Microsoft.ContainerService

# 5. Create resource group
az group create --name rg-aks-istio-gateway-demo --location eastus

# 6. Create virtual network
az network vnet create \
  --resource-group rg-aks-istio-gateway-demo \
  --name vnet-aks-istio-demo \
  --address-prefix 10.0.0.0/16 \
  --subnet-name snet-aks \
  --subnet-prefix 10.0.0.0/22

# 7. Get subnet ID
SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-aks-istio-gateway-demo \
  --vnet-name vnet-aks-istio-demo \
  --name snet-aks \
  --query id -o tsv)

# 8. Create AKS cluster with Gateway API and Istio
az aks create \
  --resource-group rg-aks-istio-gateway-demo \
  --name aks-istio-gateway-demo \
  --location eastus \
  --kubernetes-version 1.31 \
  --node-count 2 \
  --node-vm-size Standard_D4s_v5 \
  --network-plugin azure \
  --vnet-subnet-id "$SUBNET_ID" \
  --service-cidr 10.1.0.0/16 \
  --dns-service-ip 10.1.0.10 \
  --enable-managed-identity \
  --enable-gateway-api \
  --enable-app-routing-istio \
  --tier standard \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3

# 9. Get credentials
az aks get-credentials \
  --resource-group rg-aks-istio-gateway-demo \
  --name aks-istio-gateway-demo \
  --overwrite-existing

# 10. Verify Istio is running
kubectl get pods -n aks-istio-system

# 11. Verify GatewayClass
kubectl get gatewayclass approuting-istio

# 12. Deploy applications
kubectl apply -f kubernetes-manifests/

# 13. Wait for gateways to be programmed
kubectl wait --for=condition=programmed gateway/httpbin-gateway --timeout=300s
kubectl wait --for=condition=programmed gateway/echo-gateway --timeout=300s

# 14. Get gateway IP addresses
kubectl get gateway httpbin-gateway -o jsonpath='{.status.addresses[0].value}'
kubectl get gateway echo-gateway -o jsonpath='{.status.addresses[0].value}'
```

## 🧪 Testing the Demo

**Important**: The manifests use placeholder `__DOMAIN_NAME__` which is automatically substituted during deployment with your configured domain.

### Set Your Domain for Testing

```bash
# Use the same domain you configured during deployment
export DOMAIN_NAME="demo.example.com"  # Replace with your actual domain

# Or if you already set it during deployment, it should still be in your environment
echo "Testing with domain: $DOMAIN_NAME"
```

### 1. Get Gateway IP Addresses

```bash
HTTPBIN_IP=$(kubectl get gateway httpbin-gateway -o jsonpath='{.status.addresses[0].value}')
ECHO_IP=$(kubectl get gateway echo-gateway -o jsonpath='{.status.addresses[0].value}')

echo "httpbin Gateway: $HTTPBIN_IP"
echo "echo Gateway: $ECHO_IP"
```

### 2. Test Basic Routing with HTTPS (httpbin)

**Note:** Since we're using a self-signed certificate, add `-k` flag to curl to skip certificate verification.

```bash
# Test /get endpoint over HTTPS
curl -k -H "Host: httpbin.$DOMAIN_NAME" "https://$HTTPBIN_IP/get"

# Test /headers endpoint
curl -k -H "Host: httpbin.$DOMAIN_NAME" "https://$HTTPBIN_IP/headers"

# Test /status endpoint
curl -k -H "Host: httpbin.$DOMAIN_NAME" "https://$HTTPBIN_IP/status/200"

# Verify SSL certificate
curl -vI -k -H "Host: httpbin.$DOMAIN_NAME" "https://$HTTPBIN_IP" 2>&1 | grep -i 'subject\|issuer'
```

### 3. Test Traffic Splitting (Canary Deployment) over HTTPS

The echo-canary route splits traffic 90% to v1 and 10% to v2:

```bash
# Run multiple requests to see distribution
for i in {1..20}; do 
  curl -k -s -H "Host: echo.$DOMAIN_NAME" "https://$ECHO_IP/" | grep -o "Echo v[12]"
done

# Expected output: ~18 "Echo v1", ~2 "Echo v2"
```

### 4. Test Header-Based Routing over HTTPS

```bash
# Default route (goes to v1)
curl -k -s -H "Host: echo-headers.$DOMAIN_NAME" "https://$ECHO_IP/" | grep "Echo v"

# With version header (goes to v2)
curl -k -s -H "Host: echo-headers.$DOMAIN_NAME" -H "version: v2" "https://$ECHO_IP/" | grep "Echo v"
```

### 5. Test Path-Based Routing over HTTPS

```bash
# Route to echo-v1
curl -k -s -H "Host: app.$DOMAIN_NAME" "https://$ECHO_IP/v1/" | grep "Echo v"

# Route to echo-v2
curl -k -s -H "Host: app.$DOMAIN_NAME" "https://$ECHO_IP/v2/" | grep "Echo v"

# Route to httpbin
curl -k -s -H "Host: app.$DOMAIN_NAME" "https://$ECHO_IP/httpbin/get" | jq .
```

### 6. Verify TLS Certificate from Key Vault

```bash
# Check the TLS secret was created from Key Vault
kubectl get secret gateway-tls-secret

# Verify SecretProviderClass
kubectl get secretproviderclass gateway-tls-cert-spc -o yaml

# Check the sync pod is running
kubectl get pod tls-secret-sync

# View certificate details
kubectl get secret gateway-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A2 "Subject:\|Issuer:\|DNS:"
```

## 🔍 Exploring the Cluster

### View Istio Control Plane

```bash
# Check istiod pods
kubectl get pods -n aks-istio-system

# View istiod logs
kubectl logs -n aks-istio-system -l app=istiod --tail=50
```

### Inspect Gateway API Resources

```bash
# List GatewayClasses
kubectl get gatewayclass

# View Gateway status
kubectl get gateway
kubectl describe gateway httpbin-gateway

# View HTTPRoutes
kubeczure CLI Deployment

```bash
# Run the cleanup script
./cleanup-cli.sh

# Or manually delete the resource group
az group delete --name rg-aks-istio-gateway-demo --yes
```

### Terraform Deployment
```bash
# View the Envoy deployment
kubectl get deployment -l gateway.networking.k8s.io/gateway-name=httpbin-gateway

# View the LoadBalancer service
kubectl get service -l gateway.networking.k8s.io/gateway-name=httpbin-gateway

# View the HorizontalPodAutoscaler
kubectl get hpa -l gateway.networking.k8s.io/gateway-name=httpbin-gateway

# View the PodDisruptionBudget
kubectl get pdb -l gateway.networking.k8s.io/gateway-name=httpbin-gateway
```

## 📚 Learn More

### Gateway API Features Demonstrated

| Feature | File | Description |
|---------|------|-------------|
| Basic Gateway | `02-gateway-httproute.yaml` | Simple HTTP gateway with path-based routing |
| Traffic Splitting | `04-advanced-traffic-splitting.yaml` | Weighted routing for canary deployments |
| Header Routing | `05-header-based-routing.yaml` | Route based on HTTP headers |
| Path Routing | `06-path-based-routing.yaml` | Multiple backends on one gateway |

### Key Differences from Istio Service Mesh

| Feature | App Routing (Istio) | Istio Service Mesh Add-on |
|---------|---------------------|---------------------------|
| GatewayClass | `approuting-istio` | `istio` |
| Sidecar Injection | ❌ Not enabled | ✅ Enabled cluster-wide |
| Istio CRDs | ❌ Not installed | ✅ Installed |
| Use Case | Ingress only | Full service mesh |
| Upgrades | In-place | Canary upgrades |

**Note:** Both add-ons cannot run simultaneously on the same cluster.

## ⚠️ Current Limitations

1. **DNS & TLS Management** - Not yet automated via app routing add-on
   - Manual TLS configuration required (see [TLS docs](https://learn.microsoft.com/azure/aks/app-routing-gateway-api-tls))
2. **SNI Passthrough** - TLSRoute not supported
3. **Egress** - Egress traffic management not available
4. **Mutual Exclusivity** - Cannot run with Istio service mesh add-on

## 🧹 Cleanup

### Automated Cleanup

```bash
# Run the cleanup script
./cleanup.sh
```

### Manual Cleanup

```bash
# Delete Kubernetes resources
kubectl delete -f kubernetes-manifests/

# Destroy infrastructure
cd terraform
terraform destroy
```

## 🔗 References

### Official Documentation
- [AKS Blog: Gateway API Support](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api)
- [AKS App Routing Gateway API Quickstart](https://learn.microsoft.com/azure/aks/app-routing-gateway-api)
- [TLS with App Routing Gateway API](https://learn.microsoft.com/azure/aks/app-routing-gateway-api-tls)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)

### Related Resources
- [Ingress-NGINX Retirement Announcement](https://www.kubernetes.dev/blog/2025/11/12/ingress-nginx-retirement/)
- [Istio Service Mesh Add-on](https://learn.microsoft.com/azure/aks/istio-about)
- [Gateway API vs Ingress](https://gateway-api.sigs.k8s.io/#ingress-vs-gateway-api)

## 📝 Notes

- This feature is in **preview** - not recommended for production without thorough testing
- Feature registration can take 10-15 minutes
- AKS cluster deployment takes approximately 10-15 minutes
- Gateway programming typically completes in 1-2 minutes
- **Custom node resource group**: Uses readable name `rg-aks-istio-gateway-demo-nodes` instead of Azure's default `MC_*` format for better resource management and organization

## 🤝 Contributing

Found an issue or want to improve this demo? Contributions are welcome!

## 📄 License

This demo is provided as-is for educational purposes.

---

**Created:** June 2026  
**AKS Blog Reference:** [Announcing Gateway API support for App Routing (preview)](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api)
