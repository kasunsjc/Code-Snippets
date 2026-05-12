# Demo 02 — Multi-Tenant vClusters

In this demo you will simulate two separate development teams — **Team Alpha** and **Team Beta** — sharing the same AKS host cluster but working in completely isolated virtual clusters. Each team gets their own Kubernetes environment with independent RBAC, namespaces, and deployments.

## Learning Objectives

- Create multiple vclusters on the same host cluster
- Understand how vcluster enables platform-level multi-tenancy
- Give each team a scoped kubeconfig (no cluster-admin on the host)
- Verify that Team Alpha cannot see Team Beta's workloads and vice versa
- Understand the namespace-per-vcluster isolation model

## Concepts Explained

### Multi-Tenancy with vcluster

Traditional Kubernetes multi-tenancy uses namespaces + RBAC. This works but has limitations:

- Shared API server — misconfigured RBAC leaks cluster-level resources
- Cluster-scoped resources (CRDs, ClusterRoles) are shared
- Noisy neighbour risk for control-plane operations

vcluster gives each tenant a **dedicated API server**, solving these problems:

```
┌──────────────────────────────────────────────────────────┐
│  Host AKS Cluster                                        │
│                                                          │
│  ┌─────────────────────┐  ┌─────────────────────────┐   │
│  │ Namespace: vc-tenant-a  │  Namespace: vc-tenant-b │   │
│  │ ┌──────────────────┐│  │ ┌──────────────────────┐│   │
│  │ │  vcluster: tenant-a ││  │ vcluster: tenant-b   ││   │
│  │ │  Team Alpha only  ││  │  Team Beta only        ││   │
│  │ │                  ││  │                         ││   │
│  │ │  • own namespaces ││  │  • own namespaces      ││   │
│  │ │  • own RBAC      ││  │  • own RBAC             ││   │
│  │ │  • own CRDs      ││  │  • own CRDs             ││   │
│  │ └──────────────────┘│  │ └──────────────────────┘│   │
│  └─────────────────────┘  └─────────────────────────┘   │
│                                                          │
│  Synced pods visible to platform team only               │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

- Host AKS cluster deployed (run `../deploy.sh`)
- vcluster CLI installed (run `../install-tools.sh`)
- Demo 01 completed (familiarity with `vcluster create/connect`)

## Files

| File | Purpose |
|---|---|
| [tenant-a-values.yaml](tenant-a-values.yaml) | vcluster config for Team Alpha |
| [tenant-b-values.yaml](tenant-b-values.yaml) | vcluster config for Team Beta |
| [tenant-a-app.yaml](tenant-a-app.yaml) | Sample app for Team Alpha |
| [tenant-b-app.yaml](tenant-b-app.yaml) | Sample app for Team Beta |
| [setup-tenants.sh](setup-tenants.sh) | Full automated walkthrough script |

## Step-by-Step Walkthrough

### 1. Create both tenant vclusters

```bash
# Create namespaces for each tenant
kubectl create namespace vc-tenant-a
kubectl create namespace vc-tenant-b

# Create Team Alpha vcluster
vcluster create tenant-a \
  --namespace vc-tenant-a \
  --values tenant-a-values.yaml \
  --connect=false

# Create Team Beta vcluster
vcluster create tenant-b \
  --namespace vc-tenant-b \
  --values tenant-b-values.yaml \
  --connect=false
```

### 2. Verify host cluster sees both as separate namespaces

```bash
# On the HOST — each tenant's vcluster is isolated to its own namespace
kubectl get pods -n vc-tenant-a
kubectl get pods -n vc-tenant-b

# List all vclusters
vcluster list
```

### 3. Deploy as Team Alpha

```bash
# Connect to Team Alpha's vcluster
vcluster connect tenant-a --namespace vc-tenant-a --update-current

# Deploy Team Alpha's app
kubectl apply -f tenant-a-app.yaml

# List what Team Alpha has
kubectl get all -n team-alpha

# Can Team Alpha see Team Beta's resources? No!
kubectl get namespace vc-tenant-b 2>/dev/null || echo "Isolation confirmed — Team Beta namespace not visible"
```

### 4. Deploy as Team Beta (in a separate terminal or after disconnect)

```bash
# Disconnect from Team Alpha
vcluster disconnect

# Connect to Team Beta's vcluster
vcluster connect tenant-b --namespace vc-tenant-b --update-current

# Deploy Team Beta's app
kubectl apply -f tenant-b-app.yaml

# List what Team Beta has
kubectl get all -n team-beta
```

### 5. Observe from the host (platform engineer perspective)

```bash
# Disconnect from any vcluster
vcluster disconnect

# As the platform engineer, you see ALL synced pods
kubectl get pods -n vc-tenant-a   # Team Alpha's pods (synced)
kubectl get pods -n vc-tenant-b   # Team Beta's pods (synced)

# But each team only sees their own vcluster
```

### 6. Export scoped kubeconfigs for each team

```bash
# Export Team Alpha kubeconfig (share this with Team Alpha only)
vcluster connect tenant-a \
  --namespace vc-tenant-a \
  --update-current=false \
  --kube-config ./tenant-a-kubeconfig.yaml

# Export Team Beta kubeconfig
vcluster connect tenant-b \
  --namespace vc-tenant-b \
  --update-current=false \
  --kube-config ./tenant-b-kubeconfig.yaml

# Team Alpha uses their kubeconfig
KUBECONFIG=./tenant-a-kubeconfig.yaml kubectl get nodes
```

### 7. Install different CRDs per tenant

```bash
# Connect to Team Alpha
vcluster connect tenant-a --namespace vc-tenant-a --update-current

# Install cert-manager CRDs in Team Alpha's vcluster only
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.crds.yaml

# Disconnect
vcluster disconnect

# Connect to Team Beta — cert-manager CRDs are NOT here
vcluster connect tenant-b --namespace vc-tenant-b --update-current
kubectl get crd | grep cert-manager || echo "cert-manager CRDs not in Team Beta vcluster"
```

### 8. Clean up

```bash
vcluster disconnect
vcluster delete tenant-a --namespace vc-tenant-a --delete-namespace
vcluster delete tenant-b --namespace vc-tenant-b --delete-namespace
```

## Key Takeaways

1. **True isolation** — separate API servers means separate audit logs, RBAC, CRDs
2. **Self-service** — teams can install their own CRDs and ClusterRoles without impacting others
3. **Platform control** — the platform team manages host quotas via Kubernetes LimitRange/ResourceQuota on the tenant namespaces
4. **Lightweight overhead** — each vcluster adds only ~100-300 MiB memory on the host
5. **Scoped kubeconfigs** — tenants get kubeconfigs that only work for their vcluster

## Real-World Patterns

| Pattern | How vcluster helps |
|---|---|
| Dev/Staging environments per team | One vcluster per environment, all on one host |
| CI/CD ephemeral clusters | Create a vcluster per pipeline run, delete after |
| Customer-specific clusters (SaaS) | One vcluster per customer on a shared host |
| Feature-branch testing | One vcluster per PR/branch |

## Previous / Next

⬅️ [Demo 01 — Basic vcluster](../01-basic-vcluster/README.md)

➡️ [Demo 03 — Resource Limits & Isolation](../03-resource-limits/README.md)
