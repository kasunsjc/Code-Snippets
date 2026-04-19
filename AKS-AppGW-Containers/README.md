# AKS with Application Gateway for Containers (Gateway API)

Deploy an AKS cluster using **Application Gateway for Containers** — the next generation of Azure Application Gateway designed for Kubernetes workloads. This demo uses the **Gateway API** (the successor to Ingress) with the ALB Controller AKS add-on.

Two deployment strategies are supported:

| Strategy | Description |
|----------|-------------|
| **Managed by ALB Controller** | ALB Controller creates and manages AGFC lifecycle via the `ApplicationLoadBalancer` CRD |
| **Bring Your Own (BYO)** | AGFC resource, frontend, and association are pre-created in Azure (Bicep). The Gateway references them by resource ID |

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Azure Resource Group                                            │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Virtual Network (10.0.0.0/8)                              │  │
│  │                                                            │  │
│  │  ┌──────────────────────────────┐  ┌────────────────────┐  │  │
│  │  │  AKS Subnet (10.224.0.0/16) │  │ ALB Subnet         │  │  │
│  │  │                              │  │ (10.225.0.0/24)    │  │  │
│  │  │  ┌────────────────────────┐  │  │ Delegated to       │  │  │
│  │  │  │  AKS Cluster           │  │  │ Microsoft.Service  │  │  │
│  │  │  │  (Azure CNI Overlay)   │  │  │  Networking/       │  │  │
│  │  │  │                        │  │  │  trafficControllers│  │  │
│  │  │  │  ┌──────────────────┐  │  │  │                    │  │  │
│  │  │  │  │  ALB Controller  │  │  │  │  ┌──────────────┐  │  │  │
│  │  │  │  │  (AKS Add-on)   │◄─┼──┼──┼──┤  App Gateway │  │  │  │
│  │  │  │  └──────────────────┘  │  │  │  │  for         │  │  │  │
│  │  │  │                        │  │  │  │  Containers  │  │  │  │
│  │  │  │  ┌─────────┐          │  │  │  └──────┬───────┘  │  │  │
│  │  │  │  │ Gateway │          │  │  │         │          │  │  │
│  │  │  │  │   API   │          │  │  │    Internet        │  │  │
│  │  │  │  │Resources│          │  │  │                    │  │  │
│  │  │  │  └─────────┘          │  │  └────────────────────┘  │  │
│  │  │  │                        │  │                          │  │
│  │  │  │  ┌───────┐ ┌───────┐  │  │                          │  │
│  │  │  │  │ v1    │ │ v2    │  │  │                          │  │
│  │  │  │  │ Pods  │ │ Pods  │  │  │                          │  │
│  │  │  │  └───────┘ └───────┘  │  │                          │  │
│  │  │  └────────────────────────┘  │                          │  │
│  │  └──────────────────────────────┘                          │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────┐                                        │
│  │  Log Analytics       │                                        │
│  │  + Container Insights│                                        │
│  └──────────────────────┘                                        │
└──────────────────────────────────────────────────────────────────┘
```

## What is Application Gateway for Containers?

**Application Gateway for Containers** is a new application load balancing and dynamic traffic management product for workloads running in Kubernetes. It extends the Azure Application Gateway portfolio and is a new offering under the Application Gateway product family.

Key advantages over the traditional AGIC (Application Gateway Ingress Controller):

- **Gateway API support** — Uses the Kubernetes Gateway API standard (successor to Ingress)
- **Near real-time convergence** — Configuration changes reflect in ~5 seconds (vs. minutes with AGIC)
- **Traffic splitting** — Native weighted traffic splitting for blue-green and canary deployments
- **Mutual authentication (mTLS)** — Support for client-side and backend mTLS
- **No subnet reservation issues** — Uses a separate delegated subnet, no shared subnet complications
- **Multi-site hosting** — Host multiple sites on a single Gateway resource

## Prerequisites

- Azure CLI with `alb` and `aks-preview` extensions
- `kubectl`
- An Azure subscription in a [supported region](https://learn.microsoft.com/azure/application-gateway/for-containers/overview#supported-regions)

## Deployment Strategies

### Option 1 — ALB Controller Managed (default)

The ALB Controller manages the full AGFC lifecycle. An `ApplicationLoadBalancer` CRD is deployed into the cluster, and the controller creates the Azure resources automatically.

```bash
chmod +x deploy.sh
./deploy.sh managed
```

### Option 2 — Bring Your Own (BYO)

AGFC resources (traffic controller, frontend, association) are pre-created in Azure via Bicep. The Kubernetes Gateway resource references the existing AGFC by its Azure resource ID.

```bash
chmod +x deploy.sh
./deploy.sh byo
```

## Test the Application

Once deployed, get the gateway FQDN and test routing:

```bash
# Get the FQDN
FQDN=$(kubectl get gateway gateway-01 -n test-infra -o jsonpath='{.status.addresses[0].value}')

# Default route -> backend-v1
curl http://$FQDN/

# Path-based routing: /bar -> backend-v2
curl http://$FQDN/bar

# Header + query + path routing -> backend-v2
curl http://$FQDN/some/thing?great=example -H "magic: foo"
```

## Additional Gateway API Examples

The following examples build on the base deployment and demonstrate advanced AGFC features.

### Example 1 — Traffic Splitting / Weighted Round Robin

Split traffic across backends using weighted routing. Useful for canary and blue-green deployments.

```bash
# Apply the traffic-splitting HTTPRoute (uses existing gateway-01)
# Managed strategy
kubectl apply -f kubernetes-manifests/gateway-managed/04-traffic-splitting.yaml

# BYO strategy
kubectl apply -f kubernetes-manifests/gateway-byo/04-traffic-splitting.yaml

# Test — expect ~80% backend-v1, ~20% backend-v2
watch -n 1 curl http://$FQDN
```

> **Tip:** Edit the `weight` values in the HTTPRoute to shift traffic. Set backend-v2 to `100` and backend-v1 to `0` for a full cutover.

### Example 2 — SSL/TLS Offloading

Gateway terminates TLS on port 443 and forwards plain HTTP to backends.

```bash
# 1. Generate the listener TLS secret
chmod +x kubernetes-manifests/generate-tls-certs.sh
./kubernetes-manifests/generate-tls-certs.sh ssl-offloading

# 2. Deploy the HTTPS gateway + route
# Managed strategy
kubectl apply -f kubernetes-manifests/gateway-managed/05-ssl-offloading.yaml

# BYO strategy (requires envsubst)
envsubst < kubernetes-manifests/gateway-byo/05-ssl-offloading.yaml | kubectl apply -f -

# 3. Wait for the gateway to get an address
kubectl get gateway gateway-02-ssl -n test-infra -w

# 4. Test
SSL_FQDN=$(kubectl get gateway gateway-02-ssl -n test-infra -o jsonpath='{.status.addresses[0].value}')
curl --insecure https://$SSL_FQDN/
```

### Example 3 — Backend mTLS

End-to-end encryption with mutual TLS. AGFC terminates the client TLS connection, then establishes a new mTLS connection to the backend — presenting a client certificate for authentication.

```bash
# 1. Generate all mTLS certificates (CA, frontend, backend, client)
chmod +x kubernetes-manifests/generate-tls-certs.sh
./kubernetes-manifests/generate-tls-certs.sh backend-mtls

# 2. Deploy the mTLS nginx backend app
kubectl apply -f kubernetes-manifests/02-backend-mtls-app.yaml

# 3. Deploy the HTTPS gateway + route + BackendTLSPolicy
# Managed strategy
kubectl apply -f kubernetes-manifests/gateway-managed/06-backend-mtls.yaml

# BYO strategy (requires envsubst)
envsubst < kubernetes-manifests/gateway-byo/06-backend-mtls.yaml | kubectl apply -f -

# 4. Wait for the gateway and verify the BackendTLSPolicy
kubectl get gateway gateway-03-mtls -n test-infra -w
kubectl get backendtlspolicy mtls-app-tls-policy -n test-infra -o yaml

# 5. Test
MTLS_FQDN=$(kubectl get gateway gateway-03-mtls -n test-infra -o jsonpath='{.status.addresses[0].value}')
curl --insecure https://$MTLS_FQDN/
```

## Clean Up

```bash
chmod +x cleanup.sh
./cleanup.sh
```

## Project Structure

```
AKS-AppGW-Containers/
├── main.bicep                                # Main Bicep orchestrator (strategy param)
├── main.bicepparam                           # Parameters file
├── deploy.sh                                 # Deployment script (managed | byo)
├── cleanup.sh                                # Resource cleanup script
├── README.md
├── modules/
│   ├── aks.bicep                             # AKS cluster (CNI Overlay + OIDC + WI)
│   ├── vnet.bicep                            # VNet with delegated ALB subnet
│   ├── agfc.bicep                            # AGFC resources (BYO strategy only)
│   └── log-analytics.bicep                   # Log Analytics workspace
└── kubernetes-manifests/
    ├── 01-sample-apps.yaml                   # Backend v1 and v2 (shared)
    ├── 02-backend-mtls-app.yaml              # mTLS nginx backend (for example 3)
    ├── generate-tls-certs.sh                 # Generate TLS certs for examples 2 & 3
    ├── gateway-managed/
    │   ├── 02-gateway.yaml                   # Gateway with ALB managed annotations
    │   ├── 03-httproute.yaml                 # Path + header routing
    │   ├── 04-traffic-splitting.yaml         # Weighted round robin (80/20)
    │   ├── 05-ssl-offloading.yaml            # HTTPS Gateway + TLS termination
    │   └── 06-backend-mtls.yaml              # HTTPS Gateway + BackendTLSPolicy
    └── gateway-byo/
        ├── 02-gateway.yaml                   # Gateway with alb-id + frontend address
        ├── 03-httproute.yaml                 # Path + header routing
        ├── 04-traffic-splitting.yaml         # Weighted round robin (80/20)
        ├── 05-ssl-offloading.yaml            # HTTPS Gateway + TLS termination (BYO)
        └── 06-backend-mtls.yaml              # HTTPS Gateway + BackendTLSPolicy (BYO)
```

## How the Two Strategies Differ

### ALB Managed

1. Bicep deploys VNet, AKS, and Log Analytics (no AGFC Azure resources).
2. The deploy script creates an `ApplicationLoadBalancer` CRD in the cluster.
3. ALB Controller provisions the AGFC traffic controller in the MC resource group.
4. The Gateway annotation references the CRD by namespace/name:
   ```yaml
   annotations:
     alb.networking.azure.io/alb-namespace: alb-test-infra
     alb.networking.azure.io/alb-name: alb-test
   ```

### BYO (Bring Your Own)

1. Bicep deploys VNet, AKS, Log Analytics **and** the AGFC traffic controller, frontend, and association.
2. No `ApplicationLoadBalancer` CRD is needed.
3. The Gateway annotation references the AGFC by its Azure resource ID:
   ```yaml
   annotations:
     alb.networking.azure.io/alb-id: /subscriptions/.../trafficControllers/my-agfc
   spec:
     addresses:
       - type: alb.networking.azure.io/alb-frontend
         value: frontend
   ```

## Gateway API Resources Explained

### GatewayClass

The `azure-alb-external` GatewayClass is automatically installed by the ALB Controller add-on. It tells Kubernetes that Gateway resources referencing this class are managed by the Application Gateway for Containers.

### Gateway

The Gateway resource creates a listener on Application Gateway for Containers. The annotations differ depending on the deployment strategy (see above).

### HTTPRoute

HTTPRoutes define how traffic is routed from the Gateway to backend services. This demo includes:

| Route | Match | Backend |
|-------|-------|---------|
| Path-based | `/bar` prefix | backend-v2 |
| Header + query + path | header `magic: foo`, query `great=example`, path `/some/thing` | backend-v2 |
| Default | everything else | backend-v1 |
| Traffic split | all traffic (weighted) | 80% backend-v1, 20% backend-v2 |
| SSL offloading | HTTPS on port 443 → HTTP backend | backend-v1 |
| Backend mTLS | HTTPS → mTLS to backend | mtls-app (nginx with client cert verification) |

### BackendTLSPolicy

The `BackendTLSPolicy` CRD (API group `alb.networking.azure.io/v1`) configures mTLS between AGFC and backend services. It specifies the client certificate AGFC presents, the CA bundle to verify the backend, and the expected SNI/SAN.

## Deployment Details

### Infrastructure (Bicep)

| Resource | Description |
|----------|-------------|
| **VNet** | Two subnets — AKS nodes (`10.224.0.0/16`) and ALB association (`10.225.0.0/24`) |
| **AKS Cluster** | Azure CNI Overlay, OIDC Issuer, Workload Identity enabled |
| **Log Analytics** | Container Insights monitoring |
| **AGFC** *(BYO only)* | Traffic controller, frontend, and subnet association |

The ALB subnet is delegated to `Microsoft.ServiceNetworking/trafficControllers`, which is required for Application Gateway for Containers.

### AKS Add-on

The deploy script enables two AKS add-ons:
- `--enable-gateway-api` — Installs Gateway API CRDs
- `--enable-application-load-balancer` — Installs ALB Controller

This is the recommended approach over Helm-based deployment for managed environments.

### Role Assignments

Both strategies require these role assignments for the ALB managed identity:

| Role | Scope | GUID |
|------|-------|------|
| AppGW for Containers Configuration Manager | Resource group (BYO) or MC resource group (managed) | `fbc52c3f-28ad-4303-a892-8a056630b8f1` |
| Network Contributor | ALB subnet | `4d97b98b-1d4f-4787-a291-c67834d212e7` |

## Important Limitations

> **Note:** Application Gateway for Containers is evolving rapidly. Review the [official documentation](https://learn.microsoft.com/azure/application-gateway/for-containers/overview) for the latest status.

| Limitation | Details |
|------------|---------|
| **Listener ports restricted to 80 and 443** | Gateway listeners only support port 80 (HTTP) and port 443 (HTTPS). Custom ports are not allowed. |
| **Associations limited to 1** | Each AGFC resource currently supports only **one** association (one subnet). Multiple associations are planned but not yet available. |
| **Private IP addresses not supported** | Frontends only expose a public FQDN. Private IP (internal-only) frontends are not currently supported. |
| **Subnet requires /24 or larger** | The ALB association subnet must have at least 256 available addresses. If sharing the subnet across multiple AGFC resources, calculate as `n × 256`. |
| **Backend communication is HTTP/1.1** | AGFC communicates with backends over HTTP/1.1 only (except gRPC, which uses HTTP/2). Client-to-frontend always supports HTTP/2. |
| **60-second default request timeout** | The request timeout is 60 seconds by default. Long-running downloads or streaming may fail unless the timeout is increased. |
| **Regional availability** | AGFC is available in a [subset of Azure regions](https://learn.microsoft.com/azure/application-gateway/for-containers/overview#supported-regions) only. |
| **ReferenceGrant** | Only `v1alpha1` of the Gateway API `ReferenceGrant` resource is supported. |
| **Frontends cannot be shared** | A frontend belongs exclusively to one AGFC resource and cannot be shared across multiple AGFC instances. |

## Troubleshooting

### ALB Controller pods not running

```bash
kubectl get pods -n kube-system | grep alb-controller
```

### GatewayClass not found

```bash
kubectl get gatewayclass
# Should show: azure-alb-external
```

### Gateway not getting an address

```bash
kubectl get gateway gateway-01 -n test-infra -o yaml
# Check the status.conditions for errors
```

### ApplicationLoadBalancer stuck in InProgress

```bash
kubectl get applicationloadbalancer alb-test -n alb-test-infra -o yaml
# Can take 5-6 minutes — check conditions for details
```

## References

- [Application Gateway for Containers Overview](https://learn.microsoft.com/azure/application-gateway/for-containers/overview)
- [Quickstart: Deploy ALB Controller (AKS Add-on)](https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-deploy-application-gateway-for-containers-alb-controller-addon)
- [Create AGFC — Managed by ALB Controller](https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-create-application-gateway-for-containers-managed-by-alb-controller)
- [Create AGFC — Bring Your Own Deployment](https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-create-application-gateway-for-containers-byo-deployment)
- [Path, Header & Query String Routing](https://learn.microsoft.com/azure/application-gateway/for-containers/how-to-path-header-query-string-routing-gateway-api)
- [Traffic Splitting (Weighted Round Robin)](https://learn.microsoft.com/azure/application-gateway/for-containers/how-to-traffic-splitting-gateway-api)
- [SSL/TLS Offloading](https://learn.microsoft.com/azure/application-gateway/for-containers/how-to-ssl-offloading-gateway-api)
- [Backend mTLS](https://learn.microsoft.com/azure/application-gateway/for-containers/how-to-backend-mtls-gateway-api)
- [Kubernetes Gateway API Spec](https://gateway-api.sigs.k8s.io/)
