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
./deploy.sh --demo general   # or: memory | spot | arm64 | static | all
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
