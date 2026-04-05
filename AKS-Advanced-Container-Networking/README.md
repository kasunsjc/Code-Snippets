# AKS Advanced Container Networking Services (ACNS)

Demonstrate Advanced Container Networking Services on Azure Kubernetes Service, including network observability, FQDN-based security policies, and Layer 7 traffic control.

## 📋 Overview

Advanced Container Networking Services (ACNS) is a suite of services that enhances AKS networking with three key capabilities:

| Feature | Description | Data Plane |
|---------|-------------|------------|
| **Container Network Observability** | Deep insights into network traffic via metrics and flow logs | Cilium & Non-Cilium |
| **Container Network Security** | FQDN filtering and L7 policies for pod-level security | Cilium only |
| **Container Network Performance** | eBPF host routing for optimized traffic flow | Cilium only |

> **Note**: Container Network Security and Performance features require **Azure CNI Powered by Cilium** with Kubernetes **1.29+**.

## 📁 Contents

```
AKS-Advanced-Container-Networking/
├── README.md                         # This documentation
├── main.bicep                        # Bicep template for AKS cluster with ACNS
├── main.bicepparam                   # Bicep parameter file
├── commands.azcli                    # Deployment and demo commands
├── fqdn-filtering-policy.yaml       # CiliumNetworkPolicy for FQDN filtering
├── fqdn-clusterwide-policy.yaml     # CiliumClusterwideNetworkPolicy example
├── l7-policy.yaml                   # Layer 7 CiliumNetworkPolicy
├── l7-demo-apps.yaml                # HTTP server/client apps for L7 testing
└── sample-deployment.yaml           # Test pod for FQDN filtering demo
```

## 🚀 Quick Start

### 1. Set Environment Variables

```bash
export RESOURCE_GROUP="aks-acns-demo"
export LOCATION="eastus"
export CLUSTER_NAME="aks-acns-cluster"
```

### 2. Deploy Infrastructure with Bicep

```bash
# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy AKS cluster with ACNS via Bicep
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters main.bicepparam
```

The Bicep template (`main.bicep`) provisions the AKS cluster with:
- Azure CNI with overlay mode and Cilium data plane
- ACNS enabled with observability and security features
- L7 advanced network policies (includes FQDN filtering)
- System-assigned managed identity
- Auto-scaling system node pool across 3 availability zones

Override parameters inline if needed:

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters clusterName='my-cluster' nodeCount=3 nodeVmSize='Standard_D4s_v3'
```

### 3. Get Credentials

```bash
az aks get-credentials --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP
```

## 🔒 FQDN Filtering Demo

FQDN filtering lets you define egress policies using domain names instead of IP addresses.

### Deploy the Policy and Test Pod

```bash
kubectl create ns demo
kubectl apply -f fqdn-filtering-policy.yaml -n demo
kubectl apply -f sample-deployment.yaml -n demo
```

### Test Connectivity

```bash
# Allowed - traffic to *.bing.com passes
kubectl exec -n demo deploy/demo-client -- /agnhost connect www.bing.com:80

# Blocked - traffic to other domains is denied
kubectl exec -n demo deploy/demo-client -- /agnhost connect www.example.com:80
```

### How It Works

1. The `CiliumNetworkPolicy` redirects DNS queries to the ACNS Security Agent
2. DNS resolution is allowed only for domains matching `*.bing.com`
3. The Cilium Agent updates firewall rules with FQDN-to-IP mappings
4. Non-matching domains are blocked at the network level

## 🌐 Layer 7 Policy Demo

L7 policies enable application-layer traffic control based on HTTP methods, paths, and more.

### Deploy Server, Client, and Policy

```bash
kubectl create ns l7-demo
kubectl apply -f l7-demo-apps.yaml -n l7-demo
kubectl apply -f l7-policy.yaml -n l7-demo
```

### Test L7 Enforcement

```bash
HTTP_CLIENT=$(kubectl get pod -n l7-demo -l app=http-client -o jsonpath='{.items[0].metadata.name}')

# Allowed - GET /products returns "Listing products..."
kubectl exec -n l7-demo $HTTP_CLIENT -- curl -s http://http-server:80/products

# Blocked - POST /products returns "Access Denied"
kubectl exec -n l7-demo $HTTP_CLIENT -- curl -s -X POST http://http-server:80/products

# Blocked - GET / returns "Access Denied"
kubectl exec -n l7-demo $HTTP_CLIENT -- curl -s http://http-server:80/
```

### Supported L7 Protocols

| Protocol | Use Case |
|----------|----------|
| **HTTP/HTTPS** | Filter by method, path, headers |
| **gRPC** | Control access to specific RPC services |
| **Kafka** | Manage topic-level access control |

## 📊 Observability

ACNS provides network metrics via Prometheus and Grafana integration.

### Node-Level Metrics (Cilium)

| Metric | Description |
|--------|-------------|
| `cilium_forward_count_total` | Total forwarded packet count |
| `cilium_forward_bytes_total` | Total forwarded byte count |
| `cilium_drop_count_total` | Total dropped packet count |
| `cilium_drop_bytes_total` | Total dropped byte count |

### Pod-Level Metrics (Hubble)

| Metric | Description |
|--------|-------------|
| `hubble_dns_queries_total` | DNS requests by query type |
| `hubble_dns_responses_total` | DNS responses with return codes |
| `hubble_drop_total` | Dropped packets with reasons |
| `hubble_tcp_flags_total` | TCP packets by flag |
| `hubble_flows_processed_total` | L4/L7 network flows processed |

### View Real-Time Flows

```bash
kubectl exec -n kube-system ds/cilium -- hubble observe --last 10
```

## 🔄 Enable ACNS on Existing Clusters

```bash
# Enable ACNS with FQDN filtering only
az aks update \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --enable-acns

# Enable ACNS with L7 policies (also includes FQDN filtering)
az aks update \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --enable-acns \
    --acns-advanced-networkpolicies L7
```

## ❌ Disable ACNS Features

```bash
# Disable only observability
az aks update --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
    --enable-acns --disable-acns-observability

# Disable only security
az aks update --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
    --enable-acns --disable-acns-security

# Disable all ACNS features
az aks update --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME \
    --disable-acns
```

## ⚠️ Limitations

- **FQDN wildcard**: `*.example.com` is supported, but universal `*` is not
- **Node-local DNS**: FQDN filtering not supported with node-local DNS
- **Alpine images**: May need explicit search domain patterns in DNS rules
- **L7 scale**: Latency may increase beyond 3,000 requests/second through Envoy
- **FQDN scale**: Performance may degrade beyond 1,000 requests/second
- **L7 + CCNP**: L7 policies are not supported with `CiliumClusterwideNetworkPolicy`
- **L7 + Istio**: L7 via ACNS is not compatible with Istio L7 policies
- **Windows**: Pod-level metrics are Linux-only

## 📋 Requirements

- Azure CLI 2.79.0+ with Bicep CLI (bundled)
- Azure CNI with overlay mode
- Cilium data plane
- Kubernetes 1.29+

## 🧹 Cleanup

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## 📚 Learn More

- [ACNS Overview](https://learn.microsoft.com/azure/aks/advanced-container-networking-services-overview)
- [Set Up ACNS](https://learn.microsoft.com/azure/aks/use-advanced-container-networking-services)
- [FQDN Filtering Concepts](https://learn.microsoft.com/azure/aks/container-network-security-fqdn-filtering-concepts)
- [L7 Policy Concepts](https://learn.microsoft.com/azure/aks/container-network-security-l7-policy-concepts)
- [Container Network Observability Metrics](https://learn.microsoft.com/azure/aks/container-network-observability-metrics)
- [ACNS Pricing](https://azure.microsoft.com/pricing/details/azure-container-networking-services/)

## 📄 License

This demo is provided for educational purposes.
