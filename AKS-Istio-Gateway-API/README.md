# AKS Istio Gateway API Demo

> **Blog Reference:** [Announcing Gateway API support for App Routing (preview) — AKS Blog, March 2026](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api)

If you've been running workloads on AKS for a while, you've probably used NGINX as your ingress controller. It worked — and it worked well. But in March 2026, the Ingress-NGINX project was officially retired. Security patches will continue until November 2026, but there's a clear message from the Kubernetes community: it's time to move on.

That's where this demo comes in. We'll walk through the **new AKS App Routing add-on with Istio-based Gateway API support** — Microsoft's recommended path forward. Don't let the word "Istio" worry you — you don't need to run a full service mesh. This is a much lighter approach, and it's genuinely exciting.

---

## 📖 The Story So Far: Why We're Moving Away from Ingress

The Kubernetes Ingress API was designed years ago when the primary problem was simple: "how do I get traffic into my cluster?" It solved that, but it aged poorly. Here's what you run into with Ingress in the real world:

- **Annotation overload.** Want header-based routing? Canary weights? Rate limiting? Every ingress controller invented its own proprietary annotations. Your YAML ends up littered with `nginx.ingress.kubernetes.io/...` entries that only work with that one controller.
- **The "all or nothing" ownership model.** With Ingress, whoever manages the controller owns everything. Developers can't safely self-serve their routing rules without risking breaking the platform.
- **Limited expressiveness.** Traffic splitting by weight? Header matching? You can do it, but it's clunky, annotation-driven, and non-portable.

The Kubernetes community spent years designing a replacement that addresses all of this: the **Gateway API**.

---

## 🧠 Understanding the Gateway API

The Gateway API introduces a layered model where responsibilities are clearly separated. Think of it like a building — different teams own different floors:

```
┌─────────────────────────────────────────────────────────┐
│  GatewayClass  — "What kind of gateway infrastructure?" │
│  (Managed by the Platform/Infra team)                   │
│  Example: approuting-istio                               │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│  Gateway  — "Spin up an actual gateway instance"        │
│  (Managed by Cluster Operators)                         │
│  Example: my-app-gateway listening on port 443          │
└────────────┬─────────────────────────┬──────────────────┘
             │                         │
┌────────────▼──────────┐  ┌───────────▼──────────────────┐
│  HTTPRoute            │  │  HTTPRoute                   │
│  (App Developers)     │  │  (App Developers)            │
│  /api/* → service-a   │  │  /web/* → service-b          │
└───────────────────────┘  └──────────────────────────────┘
```

**GatewayClass** is the blueprint. It defines what technology implements the gateway. AKS registers a built-in `GatewayClass` called `approuting-istio` — you don't create it, it just exists once the add-on is enabled.

**Gateway** is the actual running gateway instance. When you create a `Gateway` object pointing to `approuting-istio`, AKS automatically provisions:
- An Envoy-based proxy deployment
- An Azure Load Balancer with a public IP
- A Horizontal Pod Autoscaler (HPA) to scale Envoy under load
- A PodDisruptionBudget (PDB) to keep Envoy available during node maintenance

**HTTPRoute** is the routing rule. Developers create these independently and attach them to a Gateway. Multiple teams can deploy their own HTTPRoutes to the same Gateway without interfering with each other.

This separation of concerns is the core promise of the Gateway API — and it's a genuine improvement over the Ingress model.

---

## 🤔 Wait, Istio? Do I Need a Service Mesh?

No. This is the part that trips people up.

AKS has *two* different Istio-related features, and they're very different things:

| | **App Routing (Istio) — this demo** | Istio Service Mesh Add-on |
|---|---|---|
| **What it does** | Manages ingress traffic only | Full east-west + north-south mesh |
| **Sidecar injection** | ❌ None | ✅ Enabled cluster-wide |
| **Istio CRDs installed** | ❌ No | ✅ Yes |
| **GatewayClass name** | `approuting-istio` | `istio` |
| **Complexity** | Low | High |
| **Good for** | "I just need modern ingress" | "I need mTLS between all services, circuit breaking, observability" |
| **Can coexist?** | ❌ Not on the same cluster | ❌ Not on the same cluster |

With **App Routing (Istio)**, you get an Envoy-powered gateway managed by a lightweight Istio control plane (`istiod`) — but that control plane *only* manages the gateway pods. Your application pods know nothing about Istio. No sidecars, no mesh, no complexity.

It's the best of both worlds: Envoy's performance and capabilities, without the operational overhead of a full service mesh.

---

## 🏗️ How Everything Fits Together

Here's the full picture of what this demo builds and how the pieces connect:

```
┌──────────────────────────────────────────────────────────────┐
│                     Azure Key Vault                           │
│   ┌──────────────────────────────────────────────────────┐   │
│   │  SSL/TLS Certificate (PFX)                            │   │
│   │  - Subject: *.yourdomain.com                          │   │
│   │  - Self-signed (or bring your own CA certificate)     │   │
│   └────────────────────┬─────────────────────────────────┘   │
└────────────────────────┼──────────────────────────────────────┘
                         │
                         │  CSI Secrets Store Driver
                         │  (Polls Key Vault every 2 min, syncs to K8s Secret)
                         ▼
┌──────────────────────────────────────────────────────────────┐
│            Kubernetes Secret: gateway-tls-secret              │
│                  (type: kubernetes.io/tls)                    │
└────────────────────────┬─────────────────────────────────────┘
                         │ referenced by Gateway TLS config
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Azure Load Balancer                        │
│              (Public IP, auto-provisioned by AKS)           │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│           Envoy Gateway  (approuting-istio)                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  HPA-managed Envoy pods (auto-scales 2–5)            │   │
│  │  Listener: :80  HTTP                                 │   │
│  │  Listener: :443 HTTPS  ← TLS terminated here        │   │
│  └──────────────────────────────────────────────────────┘   │
└────────┬──────────────────┬────────────────┬────────────────┘
         │                  │                │
  ┌──────▼──────┐  ┌────────▼──────┐  ┌──────▼──────────┐
  │  HTTPRoute  │  │  HTTPRoute    │  │  HTTPRoute      │
  │  (httpbin)  │  │  (echo-canary)│  │  (path-based)   │
  └──────┬──────┘  └──────┬────────┘  └──────┬──────────┘
         │                │                  │
  ┌──────▼──────┐  ┌───────▼──┐  ┌──────┐  ┌─▼───────┐
  │   httpbin   │  │ echo-v1  │  │echo-v2│  │echo-v1/2│
  │  Service    │  │  (90%)   │  │ (10%) │  │         │
  └─────────────┘  └──────────┘  └───────┘  └─────────┘
```

### The SSL/TLS Certificate Pipeline in Detail

One of the interesting parts of this setup is how certificates travel from Azure Key Vault into the Envoy gateway. Let's trace the full journey:

1. **You upload a certificate** (PFX format) to Azure Key Vault. The deploy script does this automatically — either generating a self-signed cert or importing the one you provide.

2. **The AKS CSI Secrets Store Driver** runs as a DaemonSet on every node. When a pod mounts a `SecretProviderClass` volume, the driver uses the AKS managed identity to authenticate to Key Vault and fetch the secret.

3. **The `SecretProviderClass` object** maps the Key Vault certificate to a Kubernetes `kubernetes.io/tls` Secret called `gateway-tls-secret`. A certificate imported via `az keyvault certificate import` stores its private key and public cert as two separate logical objects in Key Vault. The driver needs to fetch them independently:

   ```yaml
   objects: |
     array:
       - objectName: gateway-tls-cert
         objectType: secret   # fetches the private key
         objectAlias: "gateway-tls-key"
       - objectName: gateway-tls-cert
         objectType: cert     # fetches the public certificate
         objectAlias: "gateway-tls-crt"
   ```

   The `secretObjects` section then maps those aliases to the `tls.key` and `tls.crt` fields of the Kubernetes Secret. Using the wrong `objectType` (e.g. `secret` for both) causes the Gateway to report `InvalidCertificateRef` because the cert data is malformed.

   > **Reference:** [Secure ingress with App Routing Gateway API — AKS Docs](https://learn.microsoft.com/en-gb/azure/aks/app-routing-gateway-api-tls)

4. **The TLS sync pod** is a small busybox pod that exists solely to keep the CSI volume mounted. Without a running pod mounting the volume, the Kubernetes Secret wouldn't be created or kept updated.

5. **The Gateway** references `gateway-tls-secret` in its HTTPS listener. Envoy loads it and terminates TLS for all inbound traffic on port 443.

6. **Automatic rotation** runs every 2 minutes. If you update the certificate in Key Vault, the Kubernetes Secret is updated and Envoy picks it up — no pod restarts, no downtime.

This is a clean, production-grade approach: no secrets in YAML, full audit trail in Key Vault, automatic rotation.

---

## 🚦 Routing Patterns Explained

This demo covers four distinct routing patterns. Here's the intuition behind each.

### 1. Catch-all Routing + HTTP→HTTPS Redirect (`02-gateway-httproute.yaml`)

The httpbin gateway uses two HTTPRoutes working together:

**Catch-all HTTPS route** — no `matches` block means every path is forwarded to the backend. This is what makes `https://httpbin.yourdomain.com/` work in a browser, not just `/get`:

```yaml
hostnames:
- "httpbin.__DOMAIN_NAME__"
rules:
- backendRefs:          # no matches: block = catch-all
  - name: httpbin
    port: 8000
```

**HTTP→HTTPS redirect route** — attaches to the `http` listener (port 80) and issues a `301` redirect. Without this, browsers loading `http://` get no response at all because the HTTP listener has no route:

```yaml
parentRefs:
- name: httpbin-gateway
  sectionName: http     # port 80 listener
rules:
- filters:
  - type: RequestRedirect
    requestRedirect:
      scheme: https
      statusCode: 301
```

Notice there are no annotations anywhere — this is pure, portable Kubernetes Gateway API.

### 2. Canary / Traffic Splitting (`04-advanced-traffic-splitting.yaml`)

This is the pattern for **progressive delivery** — shipping a new version to a small slice of users first, watching for errors, then gradually expanding. The `weight` field controls the percentage split.

```yaml
hostnames:
- "echo.__DOMAIN_NAME__"
rules:
- backendRefs:
  - name: echo-v1
    port: 80
    weight: 90   # 90% of traffic goes to stable
  - name: echo-v2
    port: 80
    weight: 10   # 10% goes to the canary
```

To complete the rollout: update the weights to 0/100 and redeploy. To roll back: change it back to 100/0. This is natively expressed in the API — no external tooling required.

### 3. Header-Based Routing (`05-header-based-routing.yaml`)

Instead of splitting by percentage, route based on what's **in** the request. This is perfect for internal testing — your QA team sends a special header to always reach the new version, while regular users stay on stable.

```yaml
hostnames:
- "echo-headers.__DOMAIN_NAME__"
rules:
# If the request has "version: v2" header → go to v2
- matches:
  - headers:
    - name: version
      value: v2
  backendRefs:
  - name: echo-v2
    port: 80
# Everyone else → stable v1
- backendRefs:
  - name: echo-v1
    port: 80
```

You can match on any header value. This unlocks patterns like feature flags (`X-Feature-Flag: new-checkout`), tenant routing (`X-Tenant-ID: acme-corp`), and A/B testing — all without touching application code.

### 4. Multi-Service Path Routing (`06-path-based-routing.yaml`)

One gateway, one hostname, multiple completely different backends. A single HTTPRoute fans out traffic to the right microservice based on URL path prefix.

```yaml
hostnames:
- "app.__DOMAIN_NAME__"
rules:
- matches:
  - path: { type: PathPrefix, value: /v1 }
  backendRefs:
  - name: echo-v1
    port: 80
- matches:
  - path: { type: PathPrefix, value: /v2 }
  backendRefs:
  - name: echo-v2
    port: 80
- matches:
  - path: { type: PathPrefix, value: /httpbin }
  backendRefs:
  - name: httpbin
    port: 8000
```

This is the API gateway pattern — one public entry point, multiple internal services. The path-based fan-out lives in Kubernetes, not in a separate API Management layer.

---

## 🏗️ What Gets Deployed in Azure

Here's every Azure resource `deploy.sh` creates, and why it exists:

| Resource | Why it's there |
|---|---|
| **Resource Group** | Logical boundary for everything |
| **Virtual Network** (10.0.0.0/16) | Isolated network for the AKS cluster |
| **AKS Subnet** (10.0.0.0/22) | Provides ~1000 IPs for nodes and pods |
| **AKS Cluster** | The Kubernetes cluster itself |
| **Node Resource Group** (`rg-...-nodes`) | Custom-named RG for node VMs, NICs, disks — uses readable name instead of default `MC_*` format |
| **System-assigned Managed Identity** | AKS's identity for Azure API calls, used to access Key Vault |
| **Azure Key Vault** | Stores the TLS certificate — the source of truth for cert rotation |
| **Key Vault Secrets Provider add-on** | Syncs KV secrets into K8s Secrets via CSI driver |
| **Azure Load Balancer** | Auto-created by AKS per `Gateway` object — each Gateway gets its own public IP |
| **DNS A Records** | Created in your Azure DNS zone (if configured) — maps hostnames to gateway IPs |

---

## 🚀 Getting Started

### What You'll Need

- **Azure CLI** 2.60.0+ — [Install guide](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **kubectl** 1.30+ — [Install guide](https://kubernetes.io/docs/tasks/tools/)
- **OpenSSL** — Pre-installed on macOS and most Linux distros
- **jq** (optional, makes JSON output readable) — [Install guide](https://jqlang.github.io/jq/download/)
- An Azure subscription with Contributor access

### Enable the Preview Features

This feature is in **public preview** and requires two feature flags registered on your subscription. The `deploy.sh` script handles this automatically, but here's what it does and why:

```bash
# ManagedGatewayAPIPreview: enables Gateway API objects (GatewayClass, Gateway, HTTPRoute)
az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"

# AppRoutingIstioGatewayAPIPreview: enables the approuting-istio GatewayClass
az feature register --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview"

# Check status (run these until both show "Registered" — can take 10-15 min)
az feature show --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview" \
  --query properties.state -o tsv
az feature show --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview" \
  --query properties.state -o tsv

# Refresh the provider after both are registered
az provider register --namespace Microsoft.ContainerService
```

You'll also need the `aks-preview` CLI extension — the `--enable-gateway-api` and `--enable-app-routing-istio` flags don't exist without it:

```bash
az extension add --name aks-preview
# or update if already installed:
az extension update --name aks-preview
```

### Choosing Your Certificate

Before running the deploy, decide which certificate approach you want:

**Self-signed (default — great for this demo)**  
Leave `SSL_PFX_PATH` unset. The script generates a wildcard self-signed certificate for `*.yourdomain.com` with proper Subject Alternative Names using OpenSSL and uploads it to Key Vault. You'll need `-k` in curl commands to skip certificate verification.

**Your own CA-signed certificate**  
Export your certificate as PFX (PKCS#12 format) and point the script at it:

```bash
export SSL_PFX_PATH="/path/to/cert.pfx"
export SSL_PFX_PASSWORD="your-pfx-password"  # Leave empty if not password-protected
```

If you only have `.crt` and `.key` files, convert to PFX first:

```bash
openssl pkcs12 -export \
  -in certificate.crt \
  -inkey private.key \
  -out certificate.pfx \
  -password pass:YourPassword
```

---

## 🛠️ Deploying the Demo

### Configure and Run

All settings are controlled by environment variables. Copy the entire block below, customize the values, paste into your terminal, then run `./deploy.sh`:

```bash
#############################################
# CONFIGURATION VARIABLES
# Copy, customize, and paste this entire block
#############################################

# === Domain & SSL ===
export DOMAIN_NAME="yourdomain.com"              # Your domain — cert covers *.yourdomain.com
export SSL_PFX_PATH=""                            # Path to PFX cert (empty = auto-generate self-signed)
export SSL_PFX_PASSWORD=""                        # PFX password (empty = no password)
export CERT_NAME="gateway-tls-cert"              # Name of the cert inside Key Vault

# === Azure Resources ===
export RESOURCE_GROUP="rg-aks-istio-demo"
export NODE_RESOURCE_GROUP="rg-aks-istio-nodes"  # Node RG — VMs, disks, NICs live here
export LOCATION="eastus"
export KEYVAULT_NAME="kv-aks-istio-demo"         # Globally unique, 3-24 chars, alphanumeric

# === AKS Cluster ===
export CLUSTER_NAME="aks-istio-demo"
export K8S_VERSION="1.34"
export NODE_COUNT="2"                             # Autoscales 1–3
export NODE_SIZE="Standard_D4s_v5"

# === Network (usually fine as defaults) ===
export VNET_NAME="vnet-aks-istio-demo"
export SUBNET_NAME="snet-aks"

# === Azure DNS (optional — auto-creates A records if you have a zone) ===
export DNS_ZONE_NAME="yourdomain.com"            # Azure DNS zone name
export DNS_ZONE_RG="rg-dns"                       # RG of the DNS zone (auto-detected if empty)

# Run deployment
./deploy.sh
```

**The script is fully idempotent.** Run it twice and it won't fail — it checks whether each resource exists before creating it. This means you can safely re-run after a partial failure, or re-run to re-deploy updated manifests without rebuilding the cluster.

### What deploy.sh Does, Step by Step

| Step | What happens |
|---|---|
| 1 | Verifies `az`, `kubectl`, `openssl` are installed |
| 2 | Installs/updates `aks-preview` CLI extension |
| 3 | Registers the two preview feature flags; polls until `Registered` |
| 4 | Creates resource group (skips if exists) |
| 5 | Creates VNet + subnet (skips if exists) |
| 6 | Creates Azure Key Vault with RBAC authorization (skips if exists) |
| 7 | Generates self-signed cert with SAN **or** validates your provided PFX |
| 8 | Assigns `Key Vault Certificates Officer` to your user (skips if already assigned) |
| 9 | Imports cert to Key Vault (skips if cert already exists there) |
| 10 | Creates AKS cluster with `--enable-gateway-api --enable-app-routing-istio --enable-addons azure-keyvault-secrets-provider` (skips if exists) |
| 11 | Runs `az aks get-credentials` to configure `kubectl` |
| 12 | Assigns `Key Vault Secrets User` + `Key Vault Certificate User` roles to the AKS Secrets Provider identity |
| 13 | Creates the `SecretProviderClass` Kubernetes object |
| 14 | Waits for `istiod` pods to be ready in `aks-istio-system` |
| 15 | Verifies the `approuting-istio` GatewayClass exists |
| 16 | Deploys all manifests — substituting `__DOMAIN_NAME__` with your domain using `sed` |
| 17 | Waits for both Gateways to show `Programmed: True` (i.e., have a public IP) |
| 18 | Creates/updates DNS A records — or prints a manual DNS table if no Azure DNS zone found |
| 19 | Prints final test commands with your actual IPs and domain |

### Quick Customization Examples

```bash
# Minimal — just set your domain
export DOMAIN_NAME="mycompany.com"
./deploy.sh

# With Azure DNS auto-management
export DOMAIN_NAME="mycompany.com"
export DNS_ZONE_RG="rg-dns"
./deploy.sh

# With your own CA certificate
export DOMAIN_NAME="mycompany.com"
export SSL_PFX_PATH="/path/to/mycompany.pfx"
export SSL_PFX_PASSWORD="SecurePassword123"
./deploy.sh

# Larger cluster for load testing
export DOMAIN_NAME="mycompany.com"
export RESOURCE_GROUP="rg-aks-loadtest"
export NODE_RESOURCE_GROUP="rg-aks-loadtest-nodes"
export CLUSTER_NAME="aks-loadtest"
export NODE_COUNT="3"
export NODE_SIZE="Standard_D8s_v5"
./deploy.sh
```

### Manual Step-by-Step (if you prefer)

```bash
# 1. Install preview extension
az extension add --name aks-preview

# 2. Register features (wait for "Registered" before continuing)
az feature register --namespace "Microsoft.ContainerService" --name "ManagedGatewayAPIPreview"
az feature register --namespace "Microsoft.ContainerService" --name "AppRoutingIstioGatewayAPIPreview"
az provider register --namespace Microsoft.ContainerService

# 3. Create infrastructure
az group create --name rg-aks-istio-gateway-demo --location eastus
az network vnet create \
  --resource-group rg-aks-istio-gateway-demo \
  --name vnet-aks-istio-demo \
  --address-prefix 10.0.0.0/16 \
  --subnet-name snet-aks \
  --subnet-prefix 10.0.0.0/22

SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-aks-istio-gateway-demo \
  --vnet-name vnet-aks-istio-demo --name snet-aks --query id -o tsv)

# 4. Create AKS — three key flags:
#   --enable-gateway-api              enables Gateway API CRDs
#   --enable-app-routing-istio        registers approuting-istio GatewayClass
#   --enable-addons azure-keyvault-secrets-provider   CSI driver for KV sync
az aks create \
  --resource-group rg-aks-istio-gateway-demo \
  --name aks-istio-gateway-demo \
  --location eastus \
  --kubernetes-version 1.34 \
  --node-count 2 --node-vm-size Standard_D4s_v5 \
  --network-plugin azure --vnet-subnet-id "$SUBNET_ID" \
  --service-cidr 10.1.0.0/16 --dns-service-ip 10.1.0.10 \
  --enable-managed-identity \
  --enable-gateway-api \
  --enable-app-routing-istio \
  --enable-addons azure-keyvault-secrets-provider \
  --enable-secret-rotation --rotation-poll-interval 2m \
  --tier standard \
  --enable-cluster-autoscaler --min-count 1 --max-count 3

# 5. Configure kubectl
az aks get-credentials \
  --resource-group rg-aks-istio-gateway-demo \
  --name aks-istio-gateway-demo --overwrite-existing

# 6. Verify the GatewayClass was registered by AKS
kubectl get gatewayclass approuting-istio

# 7. Deploy apps (substitute your domain)
export DOMAIN_NAME="yourdomain.com"
for f in kubernetes-manifests/*.yaml; do
  sed "s/__DOMAIN_NAME__/$DOMAIN_NAME/g" "$f" | kubectl apply -f -
done

# 8. Wait for gateways to be programmed
kubectl wait --for=condition=programmed gateway/httpbin-gateway --timeout=300s
kubectl wait --for=condition=programmed gateway/echo-gateway --timeout=300s

# 9. Get the public IPs
kubectl get gateway -o wide
```

---

## 🧪 Testing the Demo

Once deployed, set your domain and grab the gateway IPs:

```bash
export DOMAIN_NAME="yourdomain.com"

HTTPBIN_IP=$(kubectl get gateway httpbin-gateway -o jsonpath='{.status.addresses[0].value}')
ECHO_IP=$(kubectl get gateway echo-gateway -o jsonpath='{.status.addresses[0].value}')

echo "httpbin gateway: https://httpbin.$DOMAIN_NAME  ($HTTPBIN_IP)"
echo "echo gateway:    https://echo.$DOMAIN_NAME     ($ECHO_IP)"
```

> **About `-k`:** We use `-k` to skip TLS verification for self-signed certs. Drop it if you deployed with a CA-signed certificate and have DNS pointing to the gateway IPs.

### Test 1 — Basic HTTPS routing

```bash
# Root path — works because of the catch-all route (no path restriction)
curl -k -s "https://httpbin.$DOMAIN_NAME/" | jq .url

# Any path is forwarded to httpbin
curl -k -s "https://httpbin.$DOMAIN_NAME/get" | jq .
curl -k -s "https://httpbin.$DOMAIN_NAME/headers" | jq .
curl -k -s "https://httpbin.$DOMAIN_NAME/anything/foo" | jq .

# HTTP → HTTPS redirect (expect 301, not a hang)
curl -sI --max-time 5 "http://httpbin.$DOMAIN_NAME/" | grep -i 'HTTP\|location'
# Expected:
#   HTTP/1.1 301 Moved Permanently
#   location: https://httpbin.<domain>/

# Verify the TLS certificate — should show your domain in SAN
curl -vI -k "https://httpbin.$DOMAIN_NAME" 2>&1 \
  | grep -i 'subject\|issuer\|expire'
```

### Test 2 — Canary split (90/10)

Run 20 requests — you should see roughly 18 going to v1 and 2 to v2:

```bash
for i in {1..20}; do
  curl -k -s -H "Host: echo.$DOMAIN_NAME" "https://$ECHO_IP/" | grep -o "Echo v[12]"
done | sort | uniq -c
# Expected output:
#  18 Echo v1
#   2 Echo v2
```

### Test 3 — Header-based routing

```bash
# No header → always v1
curl -k -s -H "Host: echo-headers.$DOMAIN_NAME" "https://$ECHO_IP/" | grep "Echo v"

# With "version: v2" header → always v2
curl -k -s \
  -H "Host: echo-headers.$DOMAIN_NAME" \
  -H "version: v2" \
  "https://$ECHO_IP/" | grep "Echo v"

# Any other value → falls back to v1
curl -k -s \
  -H "Host: echo-headers.$DOMAIN_NAME" \
  -H "version: v99" \
  "https://$ECHO_IP/" | grep "Echo v"
```

### Test 4 — Multi-service path routing

```bash
# /v1/* → echo-v1
curl -k -s -H "Host: app.$DOMAIN_NAME" "https://$ECHO_IP/v1/" | grep "Echo v"

# /v2/* → echo-v2
curl -k -s -H "Host: app.$DOMAIN_NAME" "https://$ECHO_IP/v2/" | grep "Echo v"

# /httpbin/* → different service entirely
curl -k -s -H "Host: app.$DOMAIN_NAME" "https://$ECHO_IP/httpbin/get" | jq .url
```

### Test 5 — Verify the Key Vault certificate sync

```bash
# Confirm the sync pod is keeping the CSI volume mounted
kubectl get pod tls-secret-sync

# Confirm the TLS secret was materialized
kubectl get secret gateway-tls-secret
# Should show: type=kubernetes.io/tls

# Inspect the certificate — should list your domain's SANs
kubectl get secret gateway-tls-secret \
  -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 -text -noout \
  | grep -A5 "Subject Alternative Name"

# Check the SecretProviderClass config
kubectl describe secretproviderclass gateway-tls-cert-spc
```

---

## 🔍 Exploring the Cluster

Once testing is done, it's worth looking at what AKS actually provisioned for you.

### The Istio control plane

```bash
# istiod runs in its own namespace and manages only the gateway Envoy pods
kubectl get pods -n aks-istio-system

# Watch istiod logs while you make requests — see Envoy xDS config pushes
kubectl logs -n aks-istio-system -l app=istiod --tail=50 -f
```

### The auto-provisioned Gateway infrastructure

Creating a single `Gateway` object causes AKS to automatically provision all of this:

```bash
# The GatewayClass that AKS registered at cluster creation
kubectl describe gatewayclass approuting-istio

# All gateways with their programmed status and public IPs
kubectl get gateway -o wide

# The Envoy deployment backing the gateway (AKS manages this)
kubectl get deployment -l gateway.networking.k8s.io/gateway-name=httpbin-gateway

# The LoadBalancer service that holds the public Azure IP
kubectl get service -l gateway.networking.k8s.io/gateway-name=httpbin-gateway

# The HPA keeping Envoy scaled with traffic
kubectl get hpa -l gateway.networking.k8s.io/gateway-name=httpbin-gateway

# The PDB preventing all Envoy pods from being evicted simultaneously
kubectl get pdb -l gateway.networking.k8s.io/gateway-name=httpbin-gateway
```

### Gateway and route status

```bash
# Full Gateway status — look for Programmed: True and listener conditions
kubectl describe gateway httpbin-gateway

# All HTTPRoutes and which gateway they're attached to
kubectl get httproute -o wide

# Detailed route status — look for Accepted: True and ResolvedRefs: True
kubectl describe httproute httpbin
```

When everything is healthy: Gateway shows `Programmed: True`, and each HTTPRoute shows `Accepted: True` with `ResolvedRefs: True`. If a route isn't working, the conditions on `kubectl describe httproute` are where to look first.

---

## 📋 Repository Structure

```
AKS-Istio-Gateway-API/
├── deploy.sh                               # Idempotent deployment script
├── cleanup.sh                              # Full cleanup including DNS records
├── README.md                               # You are here
└── kubernetes-manifests/
    ├── 00-tls-secret-sync.yaml             # Busybox pod to keep KV cert synced to K8s Secret
    ├── 01-httpbin-app.yaml                 # HTTP testing backend service
    ├── 02-gateway-httproute.yaml           # Gateway + basic path routing (httpbin)
    ├── 03-echo-apps.yaml                   # Echo v1 + v2 deployments
    ├── 04-advanced-traffic-splitting.yaml  # 90/10 canary routing (echo)
    ├── 05-header-based-routing.yaml        # Route by "version" header
    └── 06-path-based-routing.yaml          # /v1, /v2, /httpbin → different services
```

All manifests use `__DOMAIN_NAME__` as a placeholder for the hostname. `deploy.sh` substitutes it at apply time with `sed`. To apply a manifest manually:

```bash
export DOMAIN_NAME="yourdomain.com"
sed "s/__DOMAIN_NAME__/$DOMAIN_NAME/g" kubernetes-manifests/02-gateway-httproute.yaml \
  | kubectl apply -f -
```

---

## 🧹 Cleanup

The cleanup script removes everything in the right order:

```bash
./cleanup.sh
```

It will:
1. Delete all Kubernetes manifests from the cluster
2. Remove the `kubectl` context for this cluster from your kubeconfig
3. Find and delete the four DNS A records from your Azure DNS zone (auto-detected or use `DNS_ZONE_RG`)
4. Delete the Azure resource group and all resources inside it (runs async)

Monitor deletion progress with:

```bash
az group show --name rg-aks-istio-gateway-demo \
  --query properties.provisioningState -o tsv
```

---

## ⚠️ Current Limitations (as of June 2026)

**This is a preview feature** — test thoroughly before considering it for production.

| Limitation | Details |
|---|---|
| **No automated DNS/cert integration** | The App Routing add-on has external-dns + cert-manager integration for NGINX paths. This Istio path doesn't yet — we manage DNS and certs manually in this demo. |
| **No SNI passthrough** | Only `TLS mode: Terminate` is supported. `TLSRoute` for pass-through scenarios isn't available. |
| **Ingress only** | This gateway handles north-south (inbound) traffic only. East-west service-to-service traffic management requires the full Istio service mesh add-on. |
| **Mutual exclusivity** | You cannot run the Istio service mesh add-on and App Routing Istio on the same cluster — they share `istiod`. |
| **GRPCRoute maturity** | `GRPCRoute` support is still evolving — check current docs before building on it. |

---

## 📚 Further Reading

### Official Documentation

- [AKS Blog: Announcing Gateway API support for App Routing (preview)](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api) — the announcement
- [AKS App Routing Gateway API Quickstart](https://learn.microsoft.com/azure/aks/app-routing-gateway-api)
- [TLS with App Routing Gateway API](https://learn.microsoft.com/azure/aks/app-routing-gateway-api-tls)
- [Kubernetes Gateway API official documentation](https://gateway-api.sigs.k8s.io/)

### Background and Context

- [Ingress-NGINX Retirement Announcement](https://www.kubernetes.dev/blog/2025/11/12/ingress-nginx-retirement/) — why this migration matters
- [AKS Istio Service Mesh Add-on](https://learn.microsoft.com/azure/aks/istio-about) — the full mesh, when you need it
- [Gateway API vs Ingress](https://gateway-api.sigs.k8s.io/#ingress-vs-gateway-api) — official comparison
- [AKS Key Vault Secrets Provider](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver) — how the cert pipeline works

---

## 💡 Key Takeaways

- The **Gateway API** is not just "a new Ingress" — it's a fundamentally better model that properly separates platform infrastructure concerns from application routing concerns. Teams can own their own HTTPRoutes without touching each other's configuration.

- **App Routing with Istio** lets you get Envoy's capabilities (advanced load balancing, HTTP/2, header manipulation, traffic splitting) without running a service mesh. The Istio control plane manages only the gateway pods — your application pods are completely unaffected.

- **Azure Key Vault + CSI Secrets Provider** is the right way to handle TLS certificates in AKS. The certificate is never in your YAML, never in your Git history, automatically rotated, and fully audited in Key Vault.

- **The deploy script is idempotent** — run it twice, it won't fail or duplicate resources. This makes it safe to use as both an initial deployment and an update mechanism for manifests.

- **If you're starting something new today**, build it on Gateway API. The Ingress-NGINX retirement clock is ticking, and Gateway API is genuinely better — not just as a migration target but as a first-class approach to Kubernetes traffic management.

---

## 🤝 Contributing

Found a bug, got a question, or want to add another routing example? PRs are welcome.

## 📄 License

This demo is provided as-is for educational purposes.

---

**Created:** June 2026 | **Branch:** `feature/add-aks-istio-gateway-api`  
**AKS Blog Reference:** [Announcing Gateway API support for App Routing (preview)](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api)
