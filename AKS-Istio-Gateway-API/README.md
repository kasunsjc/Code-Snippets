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
- **Terraform** >= 1.9.0
- **Azure CLI** >= 2.63.0
- **kubectl** >= 1.30
- Active Azure subscription

### Azure Preview Features

This demo uses preview features that must be registered:

```bash
# Register preview features
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

### Infrastructure (Terraform)
- **AKS cluster** with Gateway API and App Routing enabled
- **Virtual Network** with dedicated AKS subnet
- **User-assigned managed identity** for AKS
- **Auto-scaling** configured for system node pool

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

### Quick Start

```bash
# 1. Navigate to the demo directory
cd AKS-Istio-Gateway-API

# 2. Run the deployment script
./deploy.sh
```

The script will:
1. ✅ Check prerequisites
2. ✅ Register Azure preview features (if needed)
3. ✅ Deploy infrastructure with Terraform
4. ✅ Configure kubectl access
5. ✅ Deploy sample applications
6. ✅ Wait for Gateways to be ready
7. ✅ Display test commands

### Manual Deployment

If you prefer manual steps:

```bash
# 1. Initialize Terraform
cd terraform
terraform init

# 2. Create terraform.tfvars (customize as needed)
cp terraform.tfvars.example terraform.tfvars

# 3. Deploy infrastructure
terraform plan
terraform apply

# 4. Get AKS credentials
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw cluster_name)
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME

# 5. Verify Istio control plane
kubectl get pods -n aks-istio-system

# 6. Deploy applications
cd ../kubernetes-manifests
kubectl apply -f .

# 7. Wait for Gateways
kubectl wait --for=condition=programmed gateway/httpbin-gateway --timeout=300s
kubectl wait --for=condition=programmed gateway/echo-gateway --timeout=300s
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
kubectl get httproute
kubectl describe httproute httpbin
```

### Check Gateway Infrastructure

When you create a Gateway, AKS automatically provisions:

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
