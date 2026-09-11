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
| `spot-optimized`      | Spot capacity, highest weight for cost savings    | `03-spot-workload.yaml`              |
| `arm64-pool`          | Arm64 (Ampere Altra) nodes for multi-arch images  | `04-arm64-workload.yaml`             |
| `static-critical`     | Fixed-size pool (`replicas: 2`), no consolidation | n/a — always-on capacity             |
| `general-purpose`     | Node/pod affinity + required pod anti-affinity    | `05-affinity-antiaffinity-workload.yaml` |
| `priority-zone-restricted` | Zone-pinned, tainted pool reserved for high-priority pods | `06-priorityclass-workload.yaml` |

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
- A Log Analytics workspace + diagnostic setting capturing the `node-auto-provisioning`
  control plane log category (Karpenter events)

### 2. Apply NodePools and a sample workload

```bash
./deploy.sh --demo general   # or: memory | spot | arm64 | static | affinity | priority | all
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

### Node affinity

`spec.affinity.nodeAffinity` terms are combined (logical AND) with each `NodePool`'s own
`spec.template.spec.requirements`. NAP only considers `NodePools` whose requirements can
still be satisfied after intersecting with the pod's required node affinity — if none can,
the pod stays `Pending` even though `NodePools` exist. Try it:

```bash
kubectl apply -f kubernetes-manifests/workloads/05-affinity-antiaffinity-workload.yaml
kubectl get pods -l app=affinity-web-demo -o wide
```

### Pod affinity / anti-affinity

- **`podAntiAffinity` (required, `topologyKey: kubernetes.io/hostname`)** forces one pod
  per node. In `05-affinity-antiaffinity-workload.yaml`, the 3 `affinity-web-demo` replicas
  each need requests that would easily fit on one node — but the anti-affinity rule makes
  NAP provision **3 separate nodes** instead of consolidating them.
- **`podAffinity` (required, same topology key)** does the opposite: the
  `affinity-cache-demo` pods must land on a node that already hosts (or is being
  provisioned for) a matching `affinity-web-demo` pod. NAP has to reason about the *other*
  pod's node affinity too, since both pods must end up co-located.
- Required pod (anti-)affinity is more expensive for the scheduler/Karpenter to evaluate
  than node affinity — prefer `preferredDuringSchedulingIgnoredDuringExecution` where a
  strict guarantee isn't necessary, and avoid it on the hot path for very large clusters.
- Consolidation respects these rules too: NAP won't merge/delete a node if doing so would
  violate a still-running pod's required anti-affinity.

### PriorityClass

`06-priorityclass-workload.yaml` defines `nap-demo-high-priority` (1000000) and
`nap-demo-low-priority` (100) and deploys low-priority "filler" pods before high-priority
"critical" pods:

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
4. **Region/zone selection.** The high-priority `critical` pods carry a `nodeAffinity` on
   `topology.kubernetes.io/zone` plus a toleration for the `dedicated=priority-zone:NoSchedule`
   taint, so NAP only provisions them onto the `priority-zone-restricted` NodePool
   ([06-priority-zone-nodepool.yaml](kubernetes-manifests/nodepools/06-priority-zone-nodepool.yaml)) —
   a NodePool that's itself restricted to a single availability zone. Low-priority pods
   have no such constraint and can land on any other NodePool/zone. This is the pattern to
   use when a priority tier of workloads must stay in a specific region/zone (e.g. for
   latency or data-residency reasons) instead of wherever NAP would otherwise place them.

   > Update the `topology.kubernetes.io/zone` value in both the NodePool and the
   > Deployment's `nodeAffinity` to a zone that exists in your region — list them with
   > `az vm list-skus --location <region> --zone --output table`.

```bash
kubectl apply -f kubernetes-manifests/nodepools/06-priority-zone-nodepool.yaml
kubectl apply -f kubernetes-manifests/workloads/06-priorityclass-workload.yaml
kubectl get pods -l app=priority-low-demo -o wide
kubectl get pods -l app=priority-high-demo -o wide
kubectl get nodes -L topology.kubernetes.io/zone,karpenter.sh/nodepool
kubectl get events --field-selector reason=Preempted
```

> Don't reuse the reserved `system-cluster-critical` / `system-node-critical`
> `PriorityClasses` for application workloads — they're meant for cluster components only.

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
