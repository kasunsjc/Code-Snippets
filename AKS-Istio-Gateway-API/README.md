# AKS Istio Gateway API Demo

This demo showcases the new **AKS App Routing with Istio-based Gateway API implementation** (preview), announced in March 2026. This feature brings modern, role-oriented traffic management to Azure Kubernetes Service without requiring a full Istio service mesh.

## 📋 Overview

The AKS app routing add-on now supports the Kubernetes Gateway API through a lightweight Istio control plane. This provides:

- **Envoy-based gateway infrastructure** - High-performance traffic routing
- **No sidecar injection** - Istio manages only the gateway, not your workloads
- **Gateway API standard** - Modern, role-oriented networking model
- **Automatic infrastructure** - AKS provisions LoadBalancer, HPA, and PDB for gateways
- **Advanced routing** - Traffic splitting, header-based routing, path-based routing

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
┌─────────────────────────────────────────────────────────┐
│                     Azure Load Balancer                  │
│                  (External IP: Programmed)               │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Gateway (approuting-istio)                  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Envoy Pods (HPA: 2-5 replicas, PDB: min 1)     │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────┬────────────────┬─────────────────────────┘
              │                │
┌─────────────▼──────┐    ┌───▼──────────────────┐
│   HTTPRoute        │    │   HTTPRoute          │
│   (httpbin)        │    │   (echo-canary)      │
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
- **jq** (optional, for JSON parsing test outputs) - [Install](https://jqlang.github.io/jq/download/)
- Active Azure subscription with contributor access

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
- **Virtual Network** with dedicated AKS subnet (10.0.0.0/16)
- **Managed identity** for AKS
- **Auto-scaling** configured for system node pool (1-3 nodes)
- **Istio control plane** (meshless) via App Routing

### Kubernetes Resources

#### Sample Applications
1. **httpbin** - HTTP testing service
2. **echo-v1** - Echo service version 1
3. **echo-v2** - Echo service version 2

#### Gateway API Resources
1. **Basic Gateway & HTTPRoute** - Simple path-based routing
2. **Traffic Splitting** - Canary deployment (90/10 split)
3. **Header-based Routing** - Route by HTTP headers
4. **Path-based Routing** - Multiple services on one gateway

## 🛠️ Deployment

### Quick Start (Automated)

```bash
# Navigate to the demo directory
cd AKS-Istio-Gateway-API

# Run the deployment script
./deploy.sh
```

The script will:
1. ✅ Check prerequisites (Azure CLI, kubectl)
2. ✅ Install/update aks-preview CLI extension
3. ✅ Register Azure preview features (if needed)
4. ✅ Create resource group and virtual network
5. ✅ Deploy AKS cluster with Gateway API and Istio app routing
6. ✅ Configure kubectl access
7. ✅ Deploy sample applications
8. ✅ Wait for Gateways to be ready
9. ✅ Display test commands and gateway IPs

**Customization:**

You can customize the deployment by setting environment variables before running the script:

```bash
export RESOURCE_GROUP="my-rg"
export LOCATION="westus2"
export CLUSTER_NAME="my-aks-cluster"
export NODE_COUNT="3"
export NODE_SIZE="Standard_D8s_v5"
export K8S_VERSION="1.31"

./deploy.sh
```

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

### 1. Get Gateway IP Addresses

```bash
HTTPBIN_IP=$(kubectl get gateway httpbin-gateway -o jsonpath='{.status.addresses[0].value}')
ECHO_IP=$(kubectl get gateway echo-gateway -o jsonpath='{.status.addresses[0].value}')

echo "httpbin Gateway: $HTTPBIN_IP"
echo "echo Gateway: $ECHO_IP"
```

### 2. Test Basic Routing (httpbin)

```bash
# Test /get endpoint
curl -H "Host: httpbin.example.com" "http://$HTTPBIN_IP/get"

# Test /headers endpoint
curl -H "Host: httpbin.example.com" "http://$HTTPBIN_IP/headers"

# Test /status endpoint
curl -H "Host: httpbin.example.com" "http://$HTTPBIN_IP/status/200"
```

### 3. Test Traffic Splitting (Canary Deployment)

The echo-canary route splits traffic 90% to v1 and 10% to v2:

```bash
# Run multiple requests to see distribution
for i in {1..20}; do 
  curl -s -H "Host: echo.example.com" "http://$ECHO_IP/" | grep -o "Echo v[12]"
done

# Expected output: ~18 "Echo v1", ~2 "Echo v2"
```

### 4. Test Header-Based Routing

```bash
# Default route (goes to v1)
curl -s -H "Host: echo-headers.example.com" "http://$ECHO_IP/" | grep "Echo v"

# With version header (goes to v2)
curl -s -H "Host: echo-headers.example.com" -H "version: v2" "http://$ECHO_IP/" | grep "Echo v"
```

### 5. Test Path-Based Routing

```bash
# Route to echo-v1
curl -s -H "Host: app.example.com" "http://$ECHO_IP/v1/" | grep "Echo v"

# Route to echo-v2
curl -s -H "Host: app.example.com" "http://$ECHO_IP/v2/" | grep "Echo v"

# Route to httpbin
curl -s -H "Host: app.example.com" "http://$ECHO_IP/httpbin/get" | jq .
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

## 🤝 Contributing

Found an issue or want to improve this demo? Contributions are welcome!

## 📄 License

This demo is provided as-is for educational purposes.

---

**Created:** June 2026  
**AKS Blog Reference:** [Announcing Gateway API support for App Routing (preview)](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api)
