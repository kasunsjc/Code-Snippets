# BYO CNI on AKS with Cilium

Deploy an AKS cluster using **Bring Your Own CNI (BYO CNI)** and install **Cilium** as the Container Network Interface. This demo includes Bicep infrastructure-as-code, automated deployment scripts, and sample applications with Cilium network policies.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Azure Resource Group                                   │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Virtual Network (10.0.0.0/16)                    │  │
│  │                                                   │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │  AKS Subnet (10.0.0.0/16)                  │  │  │
│  │  │                                             │  │  │
│  │  │  ┌───────────────────────────────────────┐  │  │  │
│  │  │  │  AKS Cluster (networkPlugin: none)    │  │  │  │
│  │  │  │                                       │  │  │  │
│  │  │  │  ┌─────────┐    ┌──────────────┐     │  │  │  │
│  │  │  │  │ System  │    │  User Pool   │     │  │  │  │
│  │  │  │  │  Pool   │    │              │     │  │  │  │
│  │  │  │  └─────────┘    └──────────────┘     │  │  │  │
│  │  │  │                                       │  │  │  │
│  │  │  │  Cilium CNI (eBPF dataplane)         │  │  │  │
│  │  │  │  ├── Cilium Agent (DaemonSet)        │  │  │  │
│  │  │  │  ├── Cilium Operator                 │  │  │  │
│  │  │  │  ├── Hubble Relay                    │  │  │  │
│  │  │  │  └── Hubble UI                       │  │  │  │
│  │  │  └───────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────┐                               │
│  │  Log Analytics       │                               │
│  │  + Container Insights│                               │
│  └──────────────────────┘                               │
└─────────────────────────────────────────────────────────┘
```

## What is BYO CNI?

By default, AKS deploys with Azure CNI or kubenet. **BYO CNI** (`networkPlugin: none`) allows you to bring your own Container Network Interface plugin — in this case **Cilium**, which provides:

- **eBPF-based dataplane** — High-performance networking without iptables
- **L3/L4/L7 Network Policies** — Fine-grained traffic control including HTTP-aware policies
- **DNS-aware Policies** — Egress filtering based on FQDN
- **Hubble Observability** — Real-time network flow visibility and metrics
- **Transparent Encryption** — WireGuard or IPsec between nodes
- **Cluster-wide Policies** — Enforce zero-trust networking across all namespaces

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

## Quick Start

### 1. Deploy Everything

```bash
chmod +x deploy.sh
./deploy.sh
```

This will:
1. Create the Azure resource group
2. Deploy the Bicep infrastructure (VNet, AKS with BYO CNI, Log Analytics)
3. Get AKS credentials
4. Install Cilium CNI via Helm
5. Enable Hubble for observability
6. Verify all nodes are Ready

### 2. Deploy Sample Apps

```bash
chmod +x sample-apps/deploy-samples.sh
./sample-apps/deploy-samples.sh
```

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

# Watch flows in the demo namespace
hubble observe -n cilium-demo --follow
```

## Sample Network Policies

### L3/L4 Policy (02-cilium-l3-l4-policy.yaml)
Allows only the `frontend` pods to access `backend-api` on port 80. All other ingress to `backend-api` is denied.

### Database Policy (03-cilium-database-policy.yaml)
Allows only `backend-api` pods to access the `database` on port 80. Frontend cannot directly access the database.

### L7 HTTP Policy (04-cilium-l7-policy.yaml)
HTTP-aware policy that restricts `backend-api` access to specific HTTP methods and URL paths:
- `GET /api/*` — allowed
- `POST /api/*` — allowed
- `GET /health` — allowed
- All other paths/methods — denied

### Cluster-wide Default Deny (05-cilium-clusterwide-policy.yaml)
Enforces a zero-trust model by denying all ingress traffic cluster-wide, except from `kube-system` pods. Use this as a baseline with explicit allow policies.

### DNS-aware Egress (06-cilium-dns-egress-policy.yaml)
Controls which external domains `backend-api` can reach:
- DNS resolution limited to `*.microsoft.com` and `*.azure.com`
- HTTPS egress only to resolved domains
- In-cluster traffic to `database` allowed

## Key Cilium Commands

```bash
# Check Cilium status
cilium status

# Run full connectivity test
cilium connectivity test

# List Cilium endpoints
kubectl -n cilium-demo get cep

# View network policies
kubectl -n cilium-demo get cnp
kubectl get ccnp  # cluster-wide policies

# Hubble observe flows
hubble observe -n cilium-demo --follow
hubble observe -n cilium-demo --verdict DROPPED
hubble observe -n cilium-demo --to-label app=database

# Check Cilium agent logs
kubectl -n kube-system logs -l app.kubernetes.io/name=cilium-agent --tail=50
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

## How It Works

1. **Bicep deploys AKS with `networkPlugin: none`** — This creates a cluster without a CNI plugin. Nodes will be in `NotReady` state until a CNI is installed.

2. **Cilium is installed via Helm** with `aksbyocni.enabled=true` — This configures Cilium to work correctly on AKS, including proper node initialization and Azure cloud integration.

3. **Hubble is enabled** for flow observability — Provides real-time visibility into network traffic, DNS queries, and policy enforcement decisions.

4. **Cilium Network Policies (CNP)** replace standard Kubernetes NetworkPolicies — CNP supports richer features like L7 filtering, DNS-aware egress, and cluster-wide enforcement.

## References

- [AKS BYO CNI Documentation](https://learn.microsoft.com/en-us/azure/aks/use-byo-cni)
- [Cilium on AKS Documentation](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/security/policy/)
- [Hubble Observability](https://docs.cilium.io/en/stable/observability/)
- [Cilium eBPF Datapath](https://docs.cilium.io/en/stable/concepts/ebpf/)
