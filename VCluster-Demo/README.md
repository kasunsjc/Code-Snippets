# vcluster Demo — Virtual Clusters on AKS

A hands-on learning environment for [vcluster](https://www.vcluster.com/) built on Azure Kubernetes Service. Work through five progressive demos to build real understanding of virtual Kubernetes clusters, from your first `vcluster create` command through to production-ready multi-tenant platforms with Ingress.

---

## What is vcluster?

**vcluster** creates fully functional Kubernetes clusters that run *inside* a namespace of a host Kubernetes cluster. Each virtual cluster has its own:

- API server (k3s, k8s, or k0s as the control plane distro)
- Controller manager and scheduler
- Separate etcd / embedded database
- Independent RBAC, namespaces, and CRDs
- Scoped kubeconfig

The virtual cluster's workload pods are **synced** to the host cluster namespace and run on the **real host nodes**. The vcluster only adds a lightweight control-plane pod (~100-300 MiB RAM).

### vcluster vs Namespaces vs Separate Clusters

| Feature | Namespace | vcluster | Separate Cluster |
|---|---|---|---|
| Isolated API server | ❌ | ✅ | ✅ |
| Separate RBAC root | ❌ | ✅ | ✅ |
| Own CRDs | ❌ | ✅ | ✅ |
| Own namespaces | ❌ | ✅ | ✅ |
| Runs on shared nodes | ✅ | ✅ | ❌ |
| Cost | Free | ~$0.05/hr | ~$0.10–$1+/hr |
| Startup time | Instant | ~30–60s | ~5–15 min |
| Cluster-admin for tenant | ❌ | ✅ | ✅ |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Azure Kubernetes Service (Host Cluster)                                 │
│  vcluster-aks-demo  /  australiaeast                                     │
│                                                                          │
│  ┌──────────────────┐  ┌─────────────────┐  ┌────────────────────────┐  │
│  │ Namespace        │  │ Namespace        │  │ Namespace              │  │
│  │ vc-basic         │  │ vc-tenant-a      │  │ vc-tenant-b            │  │
│  │                  │  │                  │  │                        │  │
│  │ ┌──────────────┐ │  │ ┌─────────────┐ │  │ ┌────────────────────┐ │  │
│  │ │vcluster:basic│ │  │ │ vcluster:   │ │  │ │ vcluster:          │ │  │
│  │ │(k3s)         │ │  │ │ tenant-a    │ │  │ │ tenant-b           │ │  │
│  │ │              │ │  │ │             │ │  │ │                    │ │  │
│  │ │ Demo 01      │ │  │ │ Team Alpha  │ │  │ │  Team Beta         │ │  │
│  │ └──────────────┘ │  │ └─────────────┘ │  │ └────────────────────┘ │  │
│  └──────────────────┘  └─────────────────┘  └────────────────────────┘  │
│                                                                          │
│  ┌──────────────────┐  ┌─────────────────┐  ┌────────────────────────┐  │
│  │ Namespace        │  │ Namespace        │  │ Namespace              │  │
│  │ vc-limits        │  │ vc-sync          │  │ vc-ingress             │  │
│  │                  │  │                  │  │                        │  │
│  │ ┌──────────────┐ │  │ ┌─────────────┐ │  │ ┌────────────────────┐ │  │
│  │ │ vcluster:    │ │  │ │ vcluster:   │ │  │ │ vcluster:          │ │  │
│  │ │ limits       │ │  │ │ sync        │ │  │ │ ingress            │ │  │
│  │ │              │ │  │ │             │ │  │ │                    │ │  │
│  │ │ Demo 03      │ │  │ │ Demo 04     │ │  │ │  Demo 05           │ │  │
│  │ └──────────────┘ │  │ └─────────────┘ │  │ └────────────────────┘ │  │
│  └──────────────────┘  └─────────────────┘  └────────────────────────┘  │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  ingress-nginx namespace                                           │  │
│  │  NGINX Ingress Controller  ←  Azure Load Balancer (Public IP)     │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  Node pools:  system (2× D2s_v3)  +  user (3× D4s_v3, autoscale 2–6)   │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
VCluster-Demo/
├── README.md                        ← You are here
├── main.bicep                       ← Host AKS cluster Bicep template
├── main.bicepparam                  ← Deployment parameters
├── deploy.sh                        ← Deploy the host AKS cluster
├── cleanup.sh                       ← Delete everything
├── install-tools.sh                 ← Install vcluster CLI + Helm + kubectl
├── modules/
│   ├── aks.bicep                    ← AKS cluster module
│   ├── vnet.bicep                   ← Virtual network module
│   └── log-analytics.bicep          ← Log Analytics module
│
├── 01-basic-vcluster/               ← Demo 01: First steps
│   ├── README.md
│   ├── vcluster-values.yaml
│   ├── demo-app.yaml
│   └── create-vcluster.sh
│
├── 02-multi-tenant/                 ← Demo 02: Two teams, one host
│   ├── README.md
│   ├── tenant-a-values.yaml
│   ├── tenant-b-values.yaml
│   ├── tenant-a-app.yaml
│   ├── tenant-b-app.yaml
│   └── setup-tenants.sh
│
├── 03-resource-limits/              ← Demo 03: Quotas & constraints
│   ├── README.md
│   ├── vcluster-with-limits.yaml
│   ├── host-namespace-quota.yaml
│   ├── workload-test.yaml
│   └── setup-limits.sh
│
├── 04-custom-sync/                  ← Demo 04: Sync architecture
│   ├── README.md
│   ├── sync-values.yaml
│   ├── test-configmap.yaml
│   ├── test-secret-host.yaml
│   └── setup-sync.sh
│
└── 05-ingress-networking/           ← Demo 05: Internet exposure
    ├── README.md
    ├── ingress-values.yaml
    ├── ingress-app.yaml
    ├── install-nginx-ingress.sh
    └── setup-ingress.sh
```

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Azure CLI | ≥ 2.55 | [docs.microsoft.com](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| kubectl | ≥ 1.29 | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Helm | ≥ 3.14 | [helm.sh](https://helm.sh/docs/intro/install/) |
| vcluster CLI | ≥ 0.20 | `brew install loft-sh/tap/vcluster` |
| Azure Subscription | — | With Contributor access |

---

## Quick Start (30-minute path)

### Step 1 — Install tools

```bash
chmod +x install-tools.sh deploy.sh cleanup.sh
./install-tools.sh
```

### Step 2 — Deploy the host AKS cluster

```bash
# Edit main.bicepparam if you want a different region/size
./deploy.sh
```

> This takes ~8 minutes and deploys an AKS cluster with 2 system nodes + 3 user nodes.

### Step 3 — Work through the demos in order

```bash
# Demo 01 — Your first vcluster (~15 min)
cd 01-basic-vcluster
chmod +x create-vcluster.sh
./create-vcluster.sh

# Demo 02 — Multi-tenant isolation (~15 min)
cd ../02-multi-tenant
chmod +x setup-tenants.sh
./setup-tenants.sh

# Demo 03 — Resource limits (~10 min)
cd ../03-resource-limits
chmod +x setup-limits.sh
./setup-limits.sh

# Demo 04 — Custom sync (~15 min)
cd ../04-custom-sync
chmod +x setup-sync.sh
./setup-sync.sh

# Demo 05 — Ingress & networking (~20 min)
cd ../05-ingress-networking
chmod +x install-nginx-ingress.sh setup-ingress.sh
./setup-ingress.sh
```

### Step 4 — Clean up everything

```bash
cd ..
./cleanup.sh
```

---

## Essential vcluster CLI Commands

```bash
# Create a vcluster
vcluster create <name> --namespace <ns> --values values.yaml

# List all vclusters (across all namespaces)
vcluster list

# Connect to a vcluster (updates current kubeconfig context)
vcluster connect <name> --namespace <ns> --update-current

# Connect and export kubeconfig to a file
vcluster connect <name> --namespace <ns> \
  --update-current=false \
  --kube-config ./my-vcluster.yaml

# Disconnect (switch back to the host context)
vcluster disconnect

# Pause a vcluster (scale down control plane, save cost)
vcluster pause <name> --namespace <ns>

# Resume a paused vcluster
vcluster resume <name> --namespace <ns>

# Delete a vcluster and its namespace
vcluster delete <name> --namespace <ns> --delete-namespace
```

---

## vcluster Configuration Reference

A `vcluster.yaml` (v0.20+) uses the following top-level sections:

```yaml
# Which Kubernetes distro to use for the virtual control plane
controlPlane:
  distro:
    k3s:           # or k8s, k0s
      enabled: true
      image:
        tag: "v1.31.0-k3s1"

  # Resource requests/limits for the control plane StatefulSet
  statefulSet:
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

# Sync configuration
sync:
  # Resources synced FROM host INTO vcluster
  fromHost:
    nodes:
      enabled: true
      selector:
        all: true         # or label selectors
    ingressClasses:
      enabled: true
    storageClasses:
      enabled: true
    configMaps:
      enabled: true
      mappings:
        - fromNamespace: host-ns
          toNamespace: kube-system
          selector:
            labelSelector:
              matchLabels:
                sync-to-vcluster: "true"

  # Resources synced FROM vcluster TO host namespace
  toHost:
    services:
      enabled: true
    persistentVolumeClaims:
      enabled: true
    ingresses:
      enabled: true   # off by default
    networkPolicies:
      enabled: true   # off by default
    configMaps:
      enabled: true
    secrets:
      enabled: true
```

---

## Demo Overview

| # | Demo | Key Skill | Time |
|---|---|---|---|
| 01 | [Basic vcluster](01-basic-vcluster/README.md) | Create, connect, deploy, explore | 15 min |
| 02 | [Multi-Tenant](02-multi-tenant/README.md) | Tenant isolation, scoped kubeconfigs | 15 min |
| 03 | [Resource Limits](03-resource-limits/README.md) | ResourceQuota, LimitRange, sizing | 10 min |
| 04 | [Custom Sync](04-custom-sync/README.md) | toHost/fromHost sync config | 15 min |
| 05 | [Ingress & Networking](05-ingress-networking/README.md) | NGINX IC, real traffic, ExternalName | 20 min |

---

## Troubleshooting

### vcluster Pod stuck in Pending

```bash
kubectl describe pod <vcluster-pod> -n <namespace>
# Common causes:
# - Insufficient CPU/memory on host nodes (user pool may need scale-out)
# - ResourceQuota on namespace (must set resources in vcluster-values.yaml)
```

### Cannot connect to vcluster

```bash
# Check the vcluster StatefulSet is Running
kubectl get statefulset -n <namespace>

# Check logs
kubectl logs <vcluster-pod-name> -n <namespace> -c syncer
kubectl logs <vcluster-pod-name> -n <namespace> -c vcluster
```

### Pods inside vcluster stuck in Pending

```bash
# Connect to vcluster and check events
vcluster connect <name> -n <namespace> --update-current
kubectl describe pod <pod-name> -n <namespace>
# Usually: insufficient resources on host nodes, or a ResourceQuota issue
```

### Ingress not working (Demo 05)

```bash
# Verify Ingress was synced to host
vcluster disconnect
kubectl get ingress -n vc-ingress

# Check NGINX IC logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# Check the Azure Load Balancer IP is assigned
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

### Wrong kubectl context

```bash
# List all contexts
kubectl config get-contexts

# Show current context
kubectl config current-context

# Switch back to host AKS
kubectl config use-context <aks-cluster-name>

# Or use vcluster disconnect
vcluster disconnect
```

---

## Learning Path & Next Steps

After completing these demos, explore these topics to go deeper:

### 1. GitOps with vcluster

Deploy vclusters via Argo CD or Flux. Each vcluster is just a Helm release — GitOps manages it naturally:

```yaml
# Argo CD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-alpha-vcluster
spec:
  source:
    repoURL: https://charts.loft.sh
    chart: vcluster
    targetRevision: 0.20.0
    helm:
      valuesFiles:
        - values/team-alpha.yaml
  destination:
    namespace: vc-team-alpha
```

### 2. vcluster Platform (Loft/vCluster Pro)

The commercial version adds:
- UI dashboard for managing vclusters
- Automatic sleep/wake for cost savings
- SSO integration
- Multi-cluster management

### 3. Ephemeral CI/CD Clusters

Create a vcluster per pull request for isolated integration testing:

```bash
# In your CI pipeline
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD | tr '/' '-')
vcluster create "ci-${BRANCH_NAME}" -n "ci-${BRANCH_NAME}"

# Run tests...

# Cleanup after tests
vcluster delete "ci-${BRANCH_NAME}" -n "ci-${BRANCH_NAME}" --delete-namespace
```

### 4. vcluster with Azure Workload Identity

Allow pods inside vclusters to use Azure Managed Identity by syncing ServiceAccount annotations and configuring the OIDC issuer.

---

## References & Further Learning

### Official Documentation

| Resource | URL |
|---|---|
| vcluster Documentation | https://www.vcluster.com/docs |
| vcluster GitHub Repository | https://github.com/loft-sh/vcluster |
| vcluster Helm Chart Values | https://github.com/loft-sh/vcluster/tree/main/chart |
| vcluster Configuration Reference | https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/ |
| vcluster Sync Reference | https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/sync/ |
| vcluster CLI Reference | https://www.vcluster.com/docs/vcluster/cli/vcluster |

### Blog Posts & Tutorials

| Title | URL |
|---|---|
| vcluster — Virtual Clusters for Kubernetes | https://loft.sh/blog/virtual-clusters-for-kubernetes/ |
| Multi-Tenancy with vcluster | https://loft.sh/blog/kubernetes-multi-tenancy-with-virtual-clusters/ |
| vcluster vs Namespaces (deep dive) | https://loft.sh/blog/kubernetes-namespaces-vs-virtual-clusters/ |
| AKS Multi-Tenancy Guide (Microsoft) | https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-cluster-isolation |
| Ingress with vcluster | https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/sync/to-host/networking/ingresses |

### Videos

| Title | Channel |
|---|---|
| vcluster — Getting Started | Loft Labs (YouTube) |
| Kubernetes Multi-Tenancy Deep Dive | KubeCon talks — search "vcluster KubeCon" |
| Platform Engineering with vcluster | CNCF YouTube |

### Related Projects

| Project | Purpose |
|---|---|
| [Loft](https://loft.sh) | Enterprise vcluster management platform |
| [DevSpace](https://devspace.sh) | Dev environments using vclusters |
| [Argo CD](https://argo-cd.readthedocs.io) | GitOps — deploy vclusters declaratively |
| [Crossplane](https://crossplane.io) | Provision vclusters as Kubernetes resources |
| [Capsule](https://capsule.clastix.io) | Namespace-based multi-tenancy (alternative) |
| [HNC](https://github.com/kubernetes-sigs/hierarchical-namespaces) | Hierarchical namespaces (alternative) |

### Kubernetes Fundamentals (if needed)

| Resource | URL |
|---|---|
| Kubernetes Docs | https://kubernetes.io/docs/home/ |
| AKS Documentation | https://learn.microsoft.com/en-us/azure/aks/ |
| Helm Docs | https://helm.sh/docs/ |
| NGINX Ingress Controller | https://kubernetes.github.io/ingress-nginx/ |

---

## Cost Estimate

Running all demos simultaneously on AKS (australiaeast, ~8 hours):

| Resource | Size | Est. Cost |
|---|---|---|
| AKS system nodes (2× D2s_v3) | 2 vCPU, 8 GiB each | ~$0.38/hr |
| AKS user nodes (3× D4s_v3) | 4 vCPU, 16 GiB each | ~$0.57/hr |
| Log Analytics (30-day retention) | Pay-per-GB | ~$0.01/hr |
| Public IP (Load Balancer) | Standard | ~$0.004/hr |
| **Total** | | **~$1.00/hr** |

> **Tip:** Delete the resource group immediately after practice to avoid ongoing costs. Run `./cleanup.sh`.

---

*Built for the YouTube Code Snippets series. Contributions welcome — open a PR on the feature branch.*
