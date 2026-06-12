# BYO CNI on AKS with Cilium

Deploy an AKS cluster using **Bring Your Own CNI (BYO CNI)** and install **Cilium** as the Container Network Interface. This demo includes Bicep infrastructure-as-code, automated deployment scripts, and sample applications with Cilium network policies.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Azure Resource Group (rg-byocni-cilium-demo)           │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Virtual Network  10.0.0.0/16                     │  │
│  │                                                   │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │  AKS Subnet  10.0.0.0/16                   │  │  │
│  │  │                                             │  │  │
│  │  │  ┌───────────────────────────────────────┐  │  │  │
│  │  │  │  AKS Cluster (networkPlugin: none)    │  │  │  │
│  │  │  │                                       │  │  │  │
│  │  │  │  ┌──────────────┐  ┌──────────────┐  │  │  │  │
│  │  │  │  │ System Pool  │  │  User Pool   │  │  │  │  │
│  │  │  │  │ D2s_v3 ×2   │  │ D4s_v3 ×2   │  │  │  │  │
│  │  │  │  │ (AzureLinux) │  │ (AzureLinux) │  │  │  │  │
│  │  │  │  └──────────────┘  └──────────────┘  │  │  │  │
│  │  │  │                                       │  │  │  │
│  │  │  │  Pod CIDR:     10.244.0.0/16          │  │  │  │
│  │  │  │  Service CIDR: 10.2.0.0/16            │  │  │  │
│  │  │  │  DNS Service:  10.2.0.10              │  │  │  │
│  │  │  │                                       │  │  │  │
│  │  │  │  ┌───────────────────────────────┐    │  │  │  │
│  │  │  │  │  Cilium CNI (eBPF dataplane)  │    │  │  │  │
│  │  │  │  │  ├── cilium (DaemonSet)       │    │  │  │  │
│  │  │  │  │  ├── cilium-operator          │    │  │  │  │
│  │  │  │  │  ├── hubble-relay             │    │  │  │  │
│  │  │  │  │  └── hubble-ui               │    │  │  │  │
│  │  │  │  └───────────────────────────────┘    │  │  │  │
│  │  │  └───────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────┐                           │
│  │  Log Analytics Workspace │                           │
│  │  + Container Insights    │                           │
│  └──────────────────────────┘                           │
│                                                         │
│  ┌──────────────────────────┐                           │
│  │  Node Resource Group     │                           │
│  │  rg-byocni-dev-nodes     │                           │
│  └──────────────────────────┘                           │
└─────────────────────────────────────────────────────────┘
```

## What is BYO CNI and Why Cilium?

### The Problem with Default AKS Networking

By default, AKS ships with two built-in networking options:

| Option | How it works | Limitations |
|--------|-------------|-------------|
| **kubenet** | Nodes get VNet IPs; pods get private overlay IPs (NAT at node level) | No direct pod-to-pod routing across nodes; limited policy support |
| **Azure CNI** | Every pod gets a real VNet IP address | Consumes large IP blocks; iptables-based kube-proxy; no L7/DNS policy |

Both options rely on **iptables** for service routing and network policy enforcement. iptables scales poorly — every connection must traverse a linear list of rules, and the entire rule table is reloaded on each policy change.

### BYO CNI (`networkPlugin: none`)

When AKS is created with `networkPlugin: none`, the control plane and node pools are provisioned **without installing any CNI plugin**. This means:

- Nodes appear in `NotReady` state immediately after cluster creation
- No pod-to-pod networking exists yet
- The operator is free to install **any** standards-compliant CNI

This is the entry point for Cilium.

### Why Cilium is the Right Choice for AKS BYO CNI

Cilium is purpose-built around **eBPF** (extended Berkeley Packet Filter), a Linux kernel technology that lets programs run safely inside the kernel without modifying kernel source. This unlocks capabilities that iptables simply cannot provide:

| Capability | iptables (kubenet / Azure CNI) | Cilium (eBPF) |
|-----------|-------------------------------|---------------|
| Dataplane | iptables rules | eBPF programs compiled into kernel |
| Policy granularity | L3/L4 (IP + port) only | L3, L4, **L7 (HTTP/gRPC/Kafka)** |
| DNS-aware egress | ❌ | ✅ FQDN-based filtering |
| Network observability | Limited (`conntrack`) | **Hubble** — per-flow visibility with labels |
| kube-proxy replacement | No | ✅ Full kube-proxy replacement via eBPF |
| Load balancer (L2) | No | ✅ L2 announcements + Gateway API |
| Transparent encryption | No | ✅ WireGuard or IPsec, zero-config |
| Cluster-wide policies | No (namespace-scoped) | ✅ `CiliumClusterwideNetworkPolicy` |
| Policy change impact | Full iptables reload | Incremental eBPF map update |

#### Key AKS-specific reasons

1. **`aksbyocni.enabled=true`** — Cilium ships a dedicated AKS mode that handles Azure-specific node initialisation (routes, interface naming, cloud metadata) so pods come up correctly on Azure VMs.

2. **No IP address waste** — Azure CNI gives every pod a VNet IP, which rapidly exhausts RFC-1918 space. With BYO CNI + Cilium's `cluster-pool` IPAM, pods use a separate `/16` CIDR (`10.244.0.0/16`) managed entirely by Cilium, independent of the VNet.

3. **kube-proxy replacement** — `kubeProxyReplacement=true` removes the kube-proxy DaemonSet entirely. Service routing happens in the kernel via eBPF, with significantly lower per-connection overhead compared to iptables-based kube-proxy (see [Cilium kube-proxy replacement benchmarks](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#performance-considerations)).

4. **Gateway API support** — Cilium acts as a native Gateway API controller (`gatewayAPI.enabled=true`), eliminating the need for a separate ingress controller.

5. **L2 announcements** — `l2announcements.enabled=true` allows Cilium to announce `LoadBalancer` service IPs directly over L2 (ARP), which is useful in non-cloud or hybrid environments.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (v2.50+)
- [Helm](https://helm.sh/docs/intro/install/) (v3.x)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli) (recommended)
- [Hubble CLI](https://docs.cilium.io/en/stable/gettingstarted/hubble_setup/#install-the-hubble-client) (recommended)

### Install CLI Tools

```bash
# Install Cilium CLI and Hubble CLI
chmod +x install-cli-tools.sh
./install-cli-tools.sh
```

## Project Structure

```
BYO-CNI-AKS/
├── main.bicep                  # Main Bicep orchestration template
├── main.bicepparam             # Parameter values
├── deploy.sh                   # Full deployment script (infra + Cilium)
├── cleanup.sh                  # Tear down all resources
├── install-cli-tools.sh        # Install Cilium & Hubble CLIs
├── README.md                   # This file
├── modules/
│   ├── aks.bicep               # AKS cluster (BYO CNI mode)
│   ├── vnet.bicep              # Virtual Network
│   └── log-analytics.bicep     # Log Analytics + Container Insights
└── sample-apps/
    ├── 00-namespace.yaml               # Demo namespace
    ├── 01-sample-app.yaml              # 3-tier app (frontend/backend/database)
    ├── 02-cilium-l3-l4-policy.yaml     # L3/L4 policy: frontend -> backend
    ├── 03-cilium-database-policy.yaml  # L3/L4 policy: backend -> database
    ├── 04-cilium-l7-policy.yaml        # L7 HTTP-aware policy
    ├── 05-cilium-clusterwide-policy.yaml # Default deny ingress (cluster-wide)
    ├── 06-cilium-dns-egress-policy.yaml  # DNS-aware egress filtering
    ├── deploy-samples.sh               # Deploy sample apps + policies
    ├── cleanup-samples.sh              # Remove sample apps
    └── test-policies.sh                # Verify network policies work
```

## Deployment Deep Dive

### Phase 1 — Infrastructure (Bicep)

`deploy.sh` runs `az deployment group create` targeting `main.bicep`, which orchestrates three Bicep modules in dependency order:

```
main.bicep
  │
  ├─► modules/log-analytics.bicep   (no dependencies)
  │     └── Log Analytics Workspace + Container Insights solution
  │
  ├─► modules/vnet.bicep            (no dependencies)
  │     └── Virtual Network  10.0.0.0/16
  │           └── aks-subnet  10.0.0.0/16  ← subnet spans the full VNet space
  │
  └─► modules/aks.bicep             (depends on vnet + log-analytics outputs)
        └── ManagedCluster
              ├── networkProfile.networkPlugin = "none"   ← BYO CNI flag
              ├── networkProfile.podCidr       = 10.244.0.0/16
              ├── networkProfile.serviceCidr   = 10.2.0.0/16
              ├── networkProfile.dnsServiceIP  = 10.2.0.10
              ├── agentPoolProfiles[system]    Standard_D2s_v3 ×2, AzureLinux
              └── agentPoolProfiles[userpool]  Standard_D4s_v3 ×2, AzureLinux
```

**What happens after Bicep completes:**

- The AKS API server and control plane are running normally.
- Worker nodes exist but are in `NotReady` state — the kubelet is running but cannot report `Ready` because there is no CNI to set up pod networking or pass the CNI health check.
- No pods (not even `kube-system` DaemonSets like `kube-proxy`) are scheduled on nodes yet, because the scheduler will not place pods on `NotReady` nodes.

> ⚠️ This is expected and correct. AKS nodes must be `NotReady` between Bicep completion and Cilium installation.

### Phase 2 — Cilium Installation (Helm)

`deploy.sh` adds the Cilium Helm repo and runs `helm upgrade --install`. The exact values used are documented below.

```bash
helm upgrade cilium cilium/cilium \
  --version 1.18.7 \
  --install \
  --namespace kube-system \
  --set aksbyocni.enabled=true \
  --set nodeinit.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enableOpenMetrics=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.244.0.0/16}" \
  --set kubeProxyReplacement=true \
  --set l2announcements.enabled=true \
  --set devices="{eth0}" \
  --set ipam.mode=cluster-pool \
  --set ingressController.enabled=true \
  --set gatewayAPI.enabled=true
```

| Helm value | What it does |
|-----------|--------------|
| `aksbyocni.enabled=true` | Activates AKS-specific node bootstrap: configures routes on Azure VMs, sets up CNI config directory expected by AKS kubelet, and handles cloud-provider metadata. Without this flag, Cilium agents will fail to start on Azure nodes. |
| `nodeinit.enabled=true` | Deploys the `cilium-node-init` DaemonSet which runs before Cilium agents and prepares each node (e.g., mounts BPF filesystem, clears stale CNI state). |
| `kubeProxyReplacement=true` | Replaces kube-proxy with Cilium's eBPF-based service proxy. All `ClusterIP`, `NodePort`, `LoadBalancer`, and `ExternalIPs` routing is handled in the kernel. kube-proxy DaemonSet is not deployed. |
| `ipam.mode=cluster-pool` | Cilium operator assigns pod IP blocks from a central pool (`10.244.0.0/16`) to each node, rather than delegating to Azure IPAM. Keeps pod IPs inside a known CIDR and avoids VNet IP exhaustion. |
| `ipam.operator.clusterPoolIPv4PodCIDRList` | Defines the overall pod CIDR pool. Must match `networkProfile.podCidr` set in the Bicep AKS module. |
| `devices="{eth0}"` | Tells Cilium which network interface to attach eBPF programs to. Azure VMs use `eth0` as the primary NIC. |
| `hubble.relay.enabled=true` | Deploys Hubble Relay, which aggregates per-node flow data into a single gRPC endpoint. Required for `hubble observe` CLI commands. |
| `hubble.ui.enabled=true` | Deploys the Hubble UI web application (port 80) for browser-based flow inspection. |
| `hubble.metrics.enableOpenMetrics=true` | Exposes Hubble metrics in OpenMetrics (Prometheus) format. |
| `hubble.metrics.enabled` | Enables specific metric sets: DNS queries, dropped packets, TCP state, flow metadata, port distribution, ICMP, and L7 HTTP (with exemplar and label context). |
| `l2announcements.enabled=true` | Enables Cilium to respond to ARP requests for `LoadBalancer` service IPs using L2 announcements, useful for on-prem or hybrid scenarios. |
| `ingressController.enabled=true` | Makes Cilium act as a Kubernetes Ingress controller. Cilium creates Envoy-based listeners for `Ingress` resources. |
| `gatewayAPI.enabled=true` | Enables Cilium's Gateway API implementation. Cilium creates `GatewayClass cilium` and handles `Gateway` / `HTTPRoute` resources. |

**What happens during `helm upgrade --install`:**

1. Helm renders the Cilium manifests with the provided values and applies them to `kube-system`.
2. The `cilium-node-init` DaemonSet runs first on each node, preparing the BPF filesystem and CNI configuration directory.
3. The `cilium` DaemonSet starts one agent per node. Each agent:
   - Loads eBPF programs onto the node's network interfaces.
   - Creates the `cilium0` virtual device for pod-to-pod traffic.
   - Writes `/etc/cni/net.d/05-cilium.conf` so kubelet knows to use Cilium for pod networking.
4. Once the CNI config is in place, the kubelet CNI health check passes and nodes transition to `Ready`.
5. `cilium-operator` starts and begins assigning pod CIDRs from `10.244.0.0/16` to each node (one `/24` per node by default).

### Phase 3 — Gateway API CRDs

`deploy.sh` installs the upstream Gateway API CRDs (v1.2.1) from `kubernetes-sigs/gateway-api`. These CRDs must be installed **before** enabling the Gateway API in Cilium (or Cilium will not register as a controller). After the CRDs are applied, the script restarts the Cilium DaemonSet and Operator so they detect the new CRDs.

### Phase 4 — Verification

The script polls `kubectl get nodes` until all nodes report `Ready`, then optionally runs `cilium status --wait` for a detailed health summary. A deployment summary table is printed showing the cluster name, Cilium version, and next steps.

### Complete Deployment Flow

```
deploy.sh
  │
  ├─ 1. check_prerequisites     (az, helm, kubectl present)
  ├─ 2. create_resource_group   (az group create)
  ├─ 3. deploy_bicep            (az deployment group create)  ← ~10–15 min
  │       └── Nodes appear in NotReady state
  ├─ 4. get_outputs             (az deployment group show)
  ├─ 5. configure_aks_access    (az aks get-credentials)
  ├─ 6. wait_for_nodes          (poll kubectl get nodes ≥2)
  ├─ 7. install_cilium          (helm upgrade --install)
  │       └── Nodes transition to Ready
  ├─ 8. install_gateway_api_crds (kubectl apply Gateway API CRDs)
  │       └── cilium DaemonSet + Operator restarted
  ├─ 9. wait_for_cilium         (rollout status cilium, operator, hubble-relay)
  ├─ 10. verify_nodes           (poll until NotReady count = 0)
  └─ 11. display_summary
```

## Quick Start

### 1. Deploy Everything

```bash
chmod +x deploy.sh
./deploy.sh
```

To also deploy the Bookinfo sample application (useful for testing L7 policies):

```bash
./deploy.sh --deploy-bookinfo
```

### 2. Deploy Sample Apps

```bash
chmod +x sample-apps/deploy-samples.sh
./sample-apps/deploy-samples.sh
```

This deploys the 3-tier demo app into the `cilium-demo` namespace and applies the L3/L4 network policies. Additional policies (L7, cluster-wide, DNS) are printed as optional next steps.

### 3. Test Network Policies

```bash
chmod +x sample-apps/test-policies.sh
./sample-apps/test-policies.sh
```

### 4. Access Hubble UI

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

Open [http://localhost:12000](http://localhost:12000) in your browser.

### 5. Observe Network Flows

```bash
# Port-forward Hubble relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &

# Watch all flows in the demo namespace
hubble observe -n cilium-demo --follow

# Show only dropped flows (useful for debugging policies)
hubble observe -n cilium-demo --verdict DROPPED

# Filter by destination workload
hubble observe -n cilium-demo --to-label app=database
```

## Infrastructure Configuration

### Bicep Parameters (`main.bicepparam`)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `namePrefix` | `byocni` | Short prefix for all resource names |
| `environment` | `dev` | Environment tag; allowed: `dev`, `test`, `prod` |
| `location` | `northeurope` | Azure region |
| `kubernetesVersion` | `1.34` | AKS Kubernetes version |
| `systemNodeCount` | `2` | System node pool size (autoscales 1–3) |
| `systemNodeVmSize` | `Standard_D2s_v3` | System node VM SKU |
| `userNodeCount` | `2` | User node pool size (autoscales 1–5) |
| `userNodeVmSize` | `Standard_D4s_v3` | User node VM SKU |
| `enableMonitoring` | `true` | Enable Log Analytics + Container Insights |

### Network CIDRs

| Range | Value | Purpose |
|-------|-------|---------|
| VNet address space | `10.0.0.0/16` | Azure Virtual Network |
| AKS node subnet | `10.0.0.0/16` | Node NICs get IPs from here |
| Pod CIDR | `10.244.0.0/16` | Cilium cluster-pool IPAM (one `/24` per node) |
| Service CIDR | `10.2.0.0/16` | Kubernetes ClusterIP services |
| DNS service IP | `10.2.0.10` | CoreDNS ClusterIP |

### AKS Node Pools

| Pool | Mode | VM Size | OS | Autoscale | Taint |
|------|------|---------|-----|-----------|-------|
| `system` | System | Standard_D2s_v3 | AzureLinux | 1–3 nodes | `CriticalAddonsOnly=true:NoSchedule` |
| `userpool` | User | Standard_D4s_v3 | AzureLinux | 1–5 nodes | none |

The system pool taint ensures only critical add-ons (CoreDNS, Cilium, metrics-server) run on system nodes. All workloads go to the user pool.

## Sample Network Policies

### L3/L4 Policy (`02-cilium-l3-l4-policy.yaml`)
Allows only the `frontend` pods to access `backend-api` on port 80. All other ingress to `backend-api` is denied. This is a standard network-layer policy equivalent to a Kubernetes `NetworkPolicy` but enforced via eBPF.

### Database Policy (`03-cilium-database-policy.yaml`)
Allows only `backend-api` pods to access the `database` on port 80. Frontend cannot directly access the database, enforcing a clean 3-tier separation.

### L7 HTTP Policy (`04-cilium-l7-policy.yaml`)
HTTP-aware policy that restricts `backend-api` access to specific HTTP methods and URL paths. This policy is enforced inside the kernel — Cilium parses HTTP headers without running a sidecar proxy:
- `GET /api/*` — allowed
- `POST /api/*` — allowed
- `GET /health` — allowed
- All other paths/methods — denied with HTTP 403

> **Note:** Applying `04-cilium-l7-policy.yaml` replaces `02-cilium-l3-l4-policy.yaml` because L7 rules implicitly supersede L3/L4 rules for the same endpoint selector.

### Cluster-wide Default Deny (`05-cilium-clusterwide-policy.yaml`)
Uses a `CiliumClusterwideNetworkPolicy` (CCNP) to enforce a zero-trust baseline by denying all ingress traffic across every namespace, except from `kube-system` pods. Unlike standard `NetworkPolicy` (which is namespace-scoped and only applies to selected pods), a CCNP applies globally and can only be created by cluster admins. Apply this before deploying workloads to implement an explicit-allow posture.

### DNS-aware Egress (`06-cilium-dns-egress-policy.yaml`)
Controls which external domains `backend-api` can reach using Cilium's FQDN matching (powered by the Cilium DNS proxy):
- DNS resolution limited to `*.microsoft.com` and `*.azure.com`
- HTTPS (port 443) egress only to IPs resolved from those FQDNs
- In-cluster traffic to `database` allowed

All other external DNS queries and connections are blocked. This is impossible to enforce with standard Kubernetes `NetworkPolicy` since it has no concept of DNS names.

## Key Cilium Commands

```bash
# Check Cilium and Hubble component status
cilium status

# Run the full built-in connectivity test suite
cilium connectivity test

# List Cilium-managed endpoints in the demo namespace
kubectl -n cilium-demo get cep

# View namespace-scoped Cilium Network Policies
kubectl -n cilium-demo get cnp

# View cluster-wide policies
kubectl get ccnp

# Observe live network flows (requires Hubble relay port-forward)
hubble observe -n cilium-demo --follow
hubble observe -n cilium-demo --verdict DROPPED
hubble observe -n cilium-demo --to-label app=database

# Check Cilium agent logs on a specific node
kubectl -n kube-system logs -l app.kubernetes.io/name=cilium-agent --tail=50

# Inspect the eBPF service map (kube-proxy replacement)
kubectl -n kube-system exec -it ds/cilium -- cilium service list

# Check node-level IPAM allocations
kubectl -n kube-system exec -it ds/cilium -- cilium ip list
```

## Cleanup

### Remove sample apps only
```bash
chmod +x sample-apps/cleanup-samples.sh
./sample-apps/cleanup-samples.sh
```

### Remove everything (infrastructure + apps)
```bash
chmod +x cleanup.sh
./cleanup.sh
```

## How It Works (Summary)

1. **Bicep deploys AKS with `networkPlugin: none`** — The API server starts, but worker nodes have no CNI plugin. Kubelet reports `NotReady` because the CNI health check fails. No pods are scheduled yet.

2. **`cilium-node-init` DaemonSet runs first** — Before the main Cilium agent starts, `node-init` prepares each node: mounts the BPF filesystem (`/sys/fs/bpf`), sets up required kernel parameters, and clears stale CNI state from any previous run.

3. **Cilium agents install eBPF programs** — Each `cilium` agent pod loads eBPF programs onto `eth0` and creates the `cilium0` virtual device. The agent writes a CNI config file, causing kubelet to pass the CNI health check. Nodes transition to `Ready`.

4. **`cilium-operator` manages IPAM** — The operator assigns a `/24` pod CIDR block from `10.244.0.0/16` to each node. Pods receive IPs within their node's block without consuming any Azure VNet IPs.

5. **kube-proxy is not installed** — All service routing (ClusterIP, NodePort, LoadBalancer) is handled by eBPF programs in the kernel, programmed by Cilium. This is faster and requires no iptables rules.

6. **Hubble provides deep observability** — Hubble hooks into Cilium's eBPF datapath and records every network flow with Kubernetes metadata (namespace, pod name, labels). Flows are aggregated by Hubble Relay and viewable via the UI or CLI.

7. **Cilium Network Policies enforce zero-trust** — `CiliumNetworkPolicy` (CNP) and `CiliumClusterwideNetworkPolicy` (CCNP) extend standard Kubernetes `NetworkPolicy` with L7 rules, DNS-aware egress, and cluster-wide scope. Policies are compiled to eBPF maps for O(1) rule lookup regardless of policy count.

## References

- [AKS BYO CNI Documentation](https://learn.microsoft.com/en-us/azure/aks/use-byo-cni)
- [Cilium on AKS (BYO CNI)](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Cilium eBPF Datapath](https://docs.cilium.io/en/stable/concepts/ebpf/)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/security/policy/)
- [CiliumClusterwideNetworkPolicy](https://docs.cilium.io/en/stable/security/policy/kubernetes/#clusterwide-policies)
- [Cilium FQDN / DNS Policies](https://docs.cilium.io/en/stable/security/dns/)
- [Hubble Observability](https://docs.cilium.io/en/stable/observability/)
- [Cilium kube-proxy Replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [Cilium Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
