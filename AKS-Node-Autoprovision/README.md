# AKS Node Auto-Provisioning (NAP) Demo

Automatically provision right-sized AKS nodes for pending pods — no manual node pool
sizing required. NAP deploys and manages [Karpenter](https://karpenter.sh) on your
behalf and is **generally available** in AKS (no longer a preview feature).

## 📋 Overview

Node Auto-Provisioning (NAP) watches for pods that can't be scheduled due to
insufficient capacity, then automatically creates nodes with the VM size, family,
architecture, and capacity type (on-demand/Spot) that best fit those pods — based on
`NodePool` and `AKSNodeClass` custom resources you define.

This demo provisions an AKS cluster with NAP enabled via Terraform, then applies a set
of `NodePool` manifests and sample workloads that showcase common patterns:

| NodePool             | Purpose                                         | Sample workload                     |
| --------------------- | ------------------------------------------------ | ------------------------------------ |
| `general-purpose`     | Default landing zone, D-family, on-demand        | `01-general-purpose-workload.yaml`   |
| `memory-optimized`    | E-family, tainted for memory-heavy workloads      | `02-memory-intensive-workload.yaml`  |
| `arm64-pool`          | Arm64 (Ampere Altra) nodes for multi-arch images  | `04-arm64-workload.yaml`             |
| `static-critical`     | Fixed-size pool (`replicas: 2`), no consolidation | n/a — always-on capacity             |
| `NodePool-agnostic`   | Required pod anti-affinity/affinity — spread vs. co-locate | `05-affinity-antiaffinity-workload.yaml` |
| `priority-zone-restricted` | Zone-pinned pool used by the priority demo workloads | `06-priorityclass-workload.yaml`, `07-priorityclass-high-workload.yaml` |

## 📁 Contents

```
AKS-Node-Autoprovision/
├── README.md
├── deploy.sh                          # Terraform deploy + apply NodePools/workloads
├── cleanup.sh                         # Graceful teardown + terraform destroy
├── terraform/
│   ├── versions.tf                    # azurerm ~> 5.0 (required for node_provisioning_profile)
│   ├── variables.tf
│   ├── main.tf                        # AKS cluster with NAP + Cilium overlay + Log Analytics
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── kubernetes-manifests/
    ├── nodepools/                     # NodePool CRDs (Karpenter, managed by NAP)
    └── workloads/                     # Sample Deployments that trigger each NodePool
```

## 🚀 Quick Start

### Prerequisites

- Azure CLI `2.76.0` or later (`az --version`)
- Terraform `>= 1.6`
- `kubectl`
- An Azure subscription with `Microsoft.ContainerService` registered

### 1. Deploy the cluster

```bash
./deploy.sh
```

This runs `terraform init`/`apply` to create:

- A resource group and a custom, readable node resource group (`rg-<cluster>-nodes`)
- An AKS cluster with:
  - `node_provisioning_profile { mode = "Auto" }` (NAP enabled)
  - Azure CNI Overlay + Cilium dataplane + Standard Load Balancer (required by NAP)
  - A small `system` node pool tainted `CriticalAddonsOnly` — NAP provisions everything else
- A Log Analytics workspace + diagnostic setting capturing the `karpenter-events`
  control plane log category (NAP/Karpenter events)

### 2. Apply NodePools and a sample workload

```bash
./deploy.sh --demo general   # or: memory | arm64 | static | affinity | priority | all
```

Or apply everything manually:

```bash
kubectl apply -f kubernetes-manifests/nodepools
kubectl apply -f kubernetes-manifests/workloads
```

### 3. Watch NAP provision nodes

```bash
kubectl get nodepools
kubectl get nodeclaims -o wide -w
kubectl get nodes -L karpenter.sh/nodepool,karpenter.azure.com/sku-family,kubernetes.io/arch
kubectl get events --field-selector source=karpenter-events
```

Query the control plane logs in Log Analytics:

```kusto
AKSControlPlane
| where Category == "karpenter-events"
```

### 4. Clean up

```bash
./cleanup.sh
```

Removes workloads and `NodePools` first (so NAP can gracefully drain its nodes), then
runs `terraform destroy`.

## 🔧 Key Concepts

- **`NodePool`** — defines provisioning policy: VM requirements (`karpenter.azure.com/sku-family`,
  `karpenter.sh/capacity-type`, `kubernetes.io/arch`, zones, etc.), resource `limits`, and a
  `weight` used when multiple pools match a pod.
- **`AKSNodeClass`** — VM-level configuration (image family, OS disk size, etc.). NAP
  auto-creates a `default` AKSNodeClass that every `NodePool` in this demo reuses via
  `nodeClassRef`.
- **`NodeClaim`** — represents an in-flight or provisioned NAP-managed node; inspect with
  `kubectl get nodeclaims`.
- **Weights** — NAP evaluates every `NodePool` whose requirements a pod tolerates and
  schedules onto the one with the highest `weight` (higher wins; omitted = `0`).
- **Static NodePools** — set `spec.replicas` for fixed-size capacity that isn't
  consolidated; scale explicitly with `kubectl scale nodepool <name> --replicas=<n>`.
- **Disruption/consolidation** — `consolidationPolicy: WhenEmptyOrUnderutilized` lets NAP
  delete/right-size underutilized nodes automatically.

## 🧲 Affinity, anti-affinity, and PriorityClass in NAP

NAP (Karpenter) simulates the Kubernetes scheduler when deciding *what* node to provision
for a pending pod, so it honors the same affinity and priority rules as the built-in
scheduler — with a few NAP-specific consequences worth calling out.

### Node affinity (SKU/NodePool selection)

`spec.affinity.nodeAffinity` terms are combined (logical AND) with each `NodePool`'s own
`spec.template.spec.requirements`. NAP only considers `NodePools` whose requirements can
still be satisfied after intersecting with the pod's required node affinity — if none can,
the pod stays `Pending` even though `NodePools` exist. This is how the `memory-optimized`
and `arm64-pool` workloads steer NAP toward a specific SKU family/capacity
type via `nodeSelector`/`nodeAffinity` — see
[02-memory-intensive-workload.yaml](kubernetes-manifests/workloads/02-memory-intensive-workload.yaml).

### Pod affinity / anti-affinity (distributing workloads across nodes)

`05-affinity-antiaffinity-workload.yaml` isolates pod (anti-)affinity from any SKU/NodePool
selection, so it purely demonstrates node **distribution**:

- **`spread-demo`** uses REQUIRED `podAntiAffinity` (`topologyKey: kubernetes.io/hostname`)
  against its own label. The 3 replicas would easily fit on a single node, but the
  anti-affinity rule forces NAP to provision **3 separate nodes** — one per replica — so a
  single node failure only ever takes out one replica.
- **`affinity-cache-demo`** uses REQUIRED `podAffinity` against `spread-demo`'s label
  (same topology key) — the opposite behavior. Each `cache` replica must land on the same
  node as one of the (already spread-out) `spread-demo` pods, so NAP ends up provisioning
  a cache pod onto each of those 3 nodes too.

```bash
kubectl apply -f kubernetes-manifests/workloads/05-affinity-antiaffinity-workload.yaml
kubectl get pods -l app=spread-demo -o wide
kubectl get pods -l app=affinity-cache-demo -o wide
kubectl get nodes -L karpenter.sh/nodepool
```

- Required pod (anti-)affinity is more expensive for the scheduler/Karpenter to evaluate
  than node affinity — prefer `preferredDuringSchedulingIgnoredDuringExecution` where a
  strict guarantee isn't necessary, and avoid it on the hot path for very large clusters.
- Consolidation respects these rules too: NAP won't merge/delete a node if doing so would
  violate a still-running pod's required anti-affinity.

### PriorityClass

`06-priorityclass-workload.yaml` defines `nap-demo-high-priority` (1000000),
`nap-demo-low-priority` (100), and the low-priority filler Deployment.
`07-priorityclass-high-workload.yaml` defines the high-priority Deployment.
`deploy.sh --demo priority` applies low-priority first, waits for rollout, then applies high-priority:

1. **Preemption happens before provisioning.** If the low-priority pods already occupy
   capacity, kube-scheduler preempts (evicts) them to make room for pending high-priority
   pods on *existing* nodes first. NAP only provisions a new node if preemption alone can't
   free enough capacity.
2. **Provisioning order.** When multiple pods across priorities are simultaneously
   pending, Karpenter services higher-priority pods first, so critical workloads get
   nodes sooner during a burst of scheduling pressure.
3. **Consolidation bias.** NAP prefers to consolidate/delete nodes that only run
   low-priority, easily-rescheduled pods, and is more conservative about disrupting nodes
   that host high-priority pods.
4. **Region/zone selection.** Both priority workloads carry required `nodeAffinity` on
   `workload-type=priority-zone-restricted`, and the high-priority pods also require
   `topology.kubernetes.io/zone=northeurope-1`, so this demo provisions onto the
   `priority-zone-restricted` NodePool
   ([06-priority-zone-nodepool.yaml](kubernetes-manifests/nodepools/06-priority-zone-nodepool.yaml)) —
   a NodePool that's itself restricted to a single availability zone. This is the pattern to
   use when a priority tier of workloads must stay in a specific region/zone (e.g. for
   latency or data-residency reasons) instead of wherever NAP would otherwise place them.

   > This demo currently supports `northeurope` for the priority scenario unless you
   > update the zone pinning in both manifests.

```bash
kubectl apply -f kubernetes-manifests/nodepools/06-priority-zone-nodepool.yaml
kubectl apply -f kubernetes-manifests/workloads/06-priorityclass-workload.yaml
kubectl rollout status deployment/priority-low-demo --timeout=180s
kubectl apply -f kubernetes-manifests/workloads/07-priorityclass-high-workload.yaml
kubectl get pods -l app=priority-low-demo -o wide
kubectl get pods -l app=priority-high-demo -o wide
kubectl get nodes -L topology.kubernetes.io/zone,karpenter.sh/nodepool
kubectl get events --field-selector reason=Preempted
```

> Don't reuse the reserved `system-cluster-critical` / `system-node-critical`
> `PriorityClasses` for application workloads — they're meant for cluster components only.

## 🩺 Troubleshooting

- **Pods stuck `Pending` on a NodePool that never gets a node (no `FailedCreateNodeClaim`
  events, `kubectl get nodepools` shows `NODES: 0`).** This usually means every candidate
  VM SKU for that pool exceeds an Azure quota, so Karpenter has nothing it can launch —
  common on trial/sponsorship subscriptions with low regional vCPU quotas (including Spot,
  if you add a Spot NodePool of your own). Check quota with:

  ```bash
  az vm list-usage --location <region> -o table
  ```

  Either request a quota increase, or narrow the NodePool's `requirements` to smaller SKUs
  (e.g. add `karpenter.azure.com/sku-cpu` with operator `Lt` to bias toward 2-vCPU
  instances).
- **`ImagePullBackOff` / `ErrImagePull`.** Double-check the image reference actually
  exists (`docker manifest inspect <image>` or `crane manifest <image>`) — this bit us
  during development with a mistyped `mcr.microsoft.com/oss/nginx/nginx` reference; all
  sample workloads now use the official, multi-arch `nginx:1.27-alpine` and
  `redis:7.2-alpine` Docker Hub images.

## ⚠️ Limitations (NAP, current as of AKS GA)

- Windows node pools and IPv6 clusters aren't supported.
- Service principals aren't supported — use a system- or user-assigned managed identity.
- You can't stop a NAP-enabled cluster, and the cluster egress `outboundType` can't be
  changed after creation.
- Custom VNet deployments require a Standard Load Balancer (Basic isn't supported).
- For most production workloads, Microsoft recommends starting from
  [AKS Automatic](https://learn.microsoft.com/azure/aks/intro-aks-automatic) (NAP
  preconfigured, SLA-backed pod readiness). This demo uses AKS Standard so every NAP
  setting is explicit and easy to inspect/modify.

## 📚 Learn More

- [Overview of node auto-provisioning (NAP) in AKS](https://learn.microsoft.com/azure/aks/node-auto-provisioning)
- [Enable or disable NAP](https://learn.microsoft.com/azure/aks/use-node-auto-provisioning)
- [Configure NodePools for NAP](https://learn.microsoft.com/azure/aks/node-auto-provisioning-node-pools)
- [Karpenter concepts](https://karpenter.sh/docs/concepts/)

## 📄 License

This demo is provided for educational purposes.
