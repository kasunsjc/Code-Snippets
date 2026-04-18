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
    ├── gateway-managed/
    │   ├── 02-gateway.yaml                   # Gateway with ALB managed annotations
    │   └── 03-httproute.yaml                 # Path + header routing
    └── gateway-byo/
        ├── 02-gateway.yaml                   # Gateway with alb-id + frontend address
        └── 03-httproute.yaml                 # Path + header routing
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

| Rule | Match | Backend |
|------|-------|---------|
| Path-based | `/bar` prefix | backend-v2 |
| Header + query + path | header `magic: foo`, query `great=example`, path `/some/thing` | backend-v2 |
| Default | everything else | backend-v1 |

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
- [Kubernetes Gateway API Spec](https://gateway-api.sigs.k8s.io/)
