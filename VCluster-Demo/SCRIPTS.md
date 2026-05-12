# VCluster Demo — Script Reference Guide

This document explains all the shell scripts in the VCluster-Demo directory, their purposes, and how they work.

---

## Core Infrastructure Scripts

### `deploy.sh` — Deploy the Host AKS Cluster

**Location:** `VCluster-Demo/deploy.sh`

**Purpose:** Creates the Azure infrastructure (AKS cluster, VNet, Log Analytics) that hosts all virtual clusters.

**Run once before starting any demos:**
```bash
./deploy.sh
```

**What it does (in order):**

| Step | Function | Purpose |
|---|---|---|
| 1 | `check_prerequisites()` | Verify Azure CLI, kubectl, Helm, vcluster are installed |
| 2 | `azure_login_check()` | Confirm user is logged into Azure and pick subscription |
| 3 | `register_providers()` | Enable Azure resource providers (ContainerService, OperationalInsights, Network) |
| 4 | `create_resource_group()` | Create or verify Azure resource group exists |
| 5 | `deploy_infrastructure()` | Deploy Bicep templates (main.bicep + modules) → creates AKS cluster |
| 6 | `get_credentials()` | Download kubeconfig and merge into ~/.kube/config |

**Expected output:**
- Resource group created (or already exists)
- Bicep deployment completes (5-10 minutes)
- kubeconfig updated with new AKS cluster context

**Troubleshooting:**
- **"Not logged in to Azure CLI"** → Run `az login` first
- **"Permission denied"** → Ensure Contributor role on subscription
- **Timeout during deployment** → AKS can take 10+ minutes; re-run the script

---

### `cleanup.sh` — Delete All Vclusters and Azure Resources

**Location:** `VCluster-Demo/cleanup.sh`

**Purpose:** Completely remove all vclusters and the host AKS infrastructure.

**Run when finished with all demos:**
```bash
./cleanup.sh
```

**What it does:**

| Step | Action | Details |
|---|---|---|
| 1 | Prompt for resource group name | Default: `rg-vcluster-demo` |
| 2 | Show what will be deleted | All 6 vclusters + AKS infrastructure |
| 3 | Require "yes" confirmation | Safety check to prevent accidental deletion |
| 4 | Delete vclusters | Uses `vcluster delete` command (fallback to kubectl if vcluster CLI unavailable) |
| 5 | Delete Azure resource group | Submits async deletion; runs in background |

**Expected output:**
- Each vcluster deleted (vc-basic, vc-tenant-a, vc-tenant-b, vc-limits, vc-sync, vc-ingress)
- Resource group deletion initiated
- Deletion happens in background (check with `az group show ...`)

**Cost tip:** Run this immediately after demos to avoid ongoing costs (~$1/hour).

---

### `install-tools.sh` — Install Required CLI Tools

**Location:** `VCluster-Demo/install-tools.sh`

**Purpose:** Install vcluster CLI, kubectl, and Helm (dependencies for all demos).

**Run before first demo:**
```bash
./install-tools.sh
```

**What it does:**

| Function | Tool | Installation Method |
|---|---|---|
| `install_vcluster()` | vcluster CLI v0.20.0 | Homebrew (macOS) or GitHub binary (Linux) |
| `install_kubectl()` | kubectl | Homebrew (macOS) or k8s.io download (Linux) |
| `install_helm()` | Helm | Homebrew (macOS) or official install script (Linux) |
| `check_azure_cli()` | Azure CLI | Verify already installed (manual install link provided) |

**Key features:**
- Detects OS (macOS/Linux) and architecture (amd64/arm64)
- Skips tools already installed
- Uses Homebrew on macOS (simpler, auto-updates)
- Falls back to manual binary download on Linux

**Expected output:**
- All tools checked and version numbers displayed
- Any missing tools identified with install links

**Note:** Azure CLI must be installed manually (not covered by script).

---

## Demo Setup Scripts

### Demo 01 — `01-basic-vcluster/create-vcluster.sh`

**Purpose:** Walk through creating your first vcluster and deploying an app inside it.

**Run:**
```bash
cd 01-basic-vcluster
./create-vcluster.sh
```

**Step-by-step breakdown:**

| Step | Command | What it does |
|---|---|---|
| 1 | `kubectl create namespace vc-basic` | Create host namespace for vcluster |
| | `vcluster create basic --values vcluster-values.yaml` | Create the virtual cluster control plane |
| 2 | `kubectl rollout status statefulset/basic` | Wait for vcluster control plane to be ready |
| 3 | `kubectl get pods -n vc-basic` | Show what host sees (just the CP pod) |
| 4 | `vcluster connect basic` | Switch kubeconfig to INSIDE the vcluster |
| 5 | `kubectl get nodes`, `kubectl get namespaces` | Explore the empty vcluster (isolated!) |
| 6 | `kubectl apply -f demo-app.yaml` | Deploy nginx inside the vcluster |
| 7 | `kubectl exec verify-pod -- curl ...` | Test DNS and connectivity |
| 8 | `vcluster disconnect` | Switch back to host context |
| | Compare pods on host vs inside vcluster | See pod syncing in action |

**Key learning points:**
- Context switching: `vcluster connect` vs `vcluster disconnect`
- Pod syncing: workloads created in vcluster appear on host with mangled names
- Namespace isolation: demo-app namespace is ONLY visible inside vcluster
- Host view vs vcluster view: completely different resource lists

**Cleanup just this demo:**
```bash
vcluster delete basic --namespace vc-basic --delete-namespace
```

---

### Demo 02 — `02-multi-tenant/setup-tenants.sh`

**Purpose:** Create two vclusters side-by-side, each representing a different team/tenant.

**Run:**
```bash
cd 02-multi-tenant
./setup-tenants.sh
```

**Configuration files:**
- `tenant-a-values.yaml` — Tenant A vcluster (2 CPU, 512Mi memory requests)
- `tenant-b-values.yaml` — Tenant B vcluster (4 CPU, 1Gi memory requests)
- `tenant-a-app.yaml` — Team Alpha app (nginx frontend)
- `tenant-b-app.yaml` — Team Beta app (httpbin API)

**Step-by-step:**

| Step | Action | Output |
|---|---|---|
| 1 | Create namespaces `vc-tenant-a` and `vc-tenant-b` | Two isolated host namespaces |
| 2 | Create both vclusters with different resource configs | Different sized virtual clusters |
| 3 | Deploy Team Alpha app → connect → deploy → disconnect | nginx running in tenant-a vcluster |
| 4 | Deploy Team Beta app (same process) | httpbin running in tenant-b vcluster |
| 5 | Verify isolation | Each team can only see their own namespace |
| 6 | Export scoped kubeconfigs to `/tmp/` | `/tmp/tenant-a.yaml` and `/tmp/tenant-b.yaml` |

**Use case:** Each team gets their own admin-level Kubernetes cluster with full RBAC freedom.

---

### Demo 03 — `03-resource-limits/setup-limits.sh`

**Purpose:** Show how to constrain vcluster resource usage using Kubernetes quotas and limits.

**Run:**
```bash
cd 03-resource-limits
./setup-limits.sh
```

**Configuration files:**
- `host-namespace-quota.yaml` — ResourceQuota + LimitRange applied to HOST namespace
- `vcluster-with-limits.yaml` — vcluster config with explicit resource REQUESTS
- `workload-test.yaml` — Test nginx deployment + resource-less job

**Step-by-step:**

| Step | Command | Purpose |
|---|---|---|
| 1 | `kubectl apply host-namespace-quota.yaml` | Set host limits (4 CPU, 4Gi memory max per vcluster namespace) |
| 2 | Create vcluster with limits config | Control plane explicitly requests resources |
| 3 | Deploy well-behaved nginx | Pod fits within quota |
| 4 | Try to create greedy pod | Job container gets injected with LimitRange defaults → exceeds quota → fails |
| 5 | `kubectl describe resourcequota` | See quota usage on host |

**Key concepts:**
- **Two-layer control:** host quota prevents runaway; vcluster CP has requests to prevent eviction
- **LimitRange injection:** default limits applied to pods without explicit requests
- **Namespace isolation:** quota only applies to its namespace (one vcluster doesn't starve others)

---

### Demo 04 — `04-custom-sync/setup-sync.sh`

**Purpose:** Demonstrate how sync works — which resources flow between vcluster and host.

**Run:**
```bash
cd 04-custom-sync
./setup-sync.sh
```

**Configuration files:**
- `sync-values.yaml` — Advanced sync config (fromHost, toHost directions)
- `test-configmap.yaml` — ConfigMap on HOST with `sync-to-vcluster: "true"` label
- `test-secret-host.yaml` — Secret on HOST (for testing sync)

**Step-by-step:**

| Step | Action | Sync Direction | Visible Where |
|---|---|---|---|
| 1 | Create test resources on HOST | — | Host only |
| 2 | Create vcluster | — | — |
| 3 | Connect to vcluster | — | — |
| 4 | `kubectl get configmap` | **fromHost** | Synced into vcluster! |
| 5 | Create echo-server Ingress in vcluster | **toHost** | Synced to host namespace |
| 6 | Check host namespace | — | Ingress appears with vcluster prefix |

**Sync config sections:**
- **fromHost** — Resources copied from host INTO vcluster (nodes, ingressClasses, storageClasses, configMaps, secrets with labels)
- **toHost** — Resources created in vcluster copied to host namespace (services, PVCs, ingresses, networkPolicies)

**Use case:** Control what tenants can access (e.g., only specific ConfigMaps synced in).

---

### Demo 05 — `05-ingress-networking/setup-ingress.sh`

**Purpose:** Expose vcluster workloads to the internet via NGINX Ingress Controller.

**Run:**
```bash
cd 05-ingress-networking
./setup-ingress.sh
```

**Helper scripts:**
- `install-nginx-ingress.sh` — Install NGINX IC on host cluster first

**Configuration files:**
- `ingress-values.yaml` — vcluster with `ingresses.enabled: true`
- `ingress-app.yaml` — echo-server + Service + Ingress (nip.io host placeholder)

**Step-by-step:**

| Step | Action | Details |
|---|---|---|
| 1 | Install NGINX Ingress Controller on HOST | Helm → creates LoadBalancer service → gets public IP |
| 2 | Get Azure Load Balancer IP | Used for nip.io DNS-less testing |
| 3 | Create vcluster with Ingress sync enabled | `ingresses.enabled: true` in config |
| 4 | Deploy echo-server with Ingress inside vcluster | `sed` replaces REPLACE_WITH_HOST with `echo.<IP>.nip.io` |
| 5 | Verify Ingress synced to host | Appears in host namespace with vcluster prefix |
| 6 | Test HTTP traffic | `curl http://echo.<IP>.nip.io` → hits NGINX IC → routes to vcluster pod |

**Traffic flow:**
```
Internet Request
    ↓
Azure Load Balancer (public IP)
    ↓
NGINX Ingress Controller (on host)
    ↓
Synced Service (in host namespace, points to synced pod)
    ↓
Echo-server Pod (actually running on host node via sync)
```

**nip.io trick:** `echo.1.2.3.4.nip.io` resolves to `1.2.3.4` — no DNS setup needed for testing!

---

## Common Commands Across Scripts

### kubectl Commands

```bash
# Check current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# List pods in a namespace
kubectl get pods -n <namespace>

# Wait for deployment/StatefulSet to be ready
kubectl rollout status deployment/<name> -n <namespace> --timeout=120s
kubectl rollout status statefulset/<name> -n <namespace> --timeout=120s

# Apply YAML file
kubectl apply -f <file.yaml>

# Execute command inside a container
kubectl exec -n <namespace> <pod-name> -- <command>

# Get namespace status (verify it exists)
kubectl get namespace <name>

# Get resources of type
kubectl get <resource-type> -n <namespace>  # e.g., ingress, service, pod
```

### vcluster Commands

```bash
# Create a vcluster
vcluster create <name> --namespace <ns> --values <values-file>

# Connect to vcluster (switch context)
vcluster connect <name> --namespace <ns> --update-current

# Disconnect (switch back to host)
vcluster disconnect

# Delete a vcluster and its namespace
vcluster delete <name> --namespace <ns> --delete-namespace

# List all vclusters
vcluster list
```

### Azure CLI Commands

```bash
# Check if logged in
az account show

# List subscriptions
az account list --output table

# Check if resource group exists
az group exists --name <rg-name>

# Create resource group
az group create --name <rg-name> --location <region>

# Delete resource group (async)
az group delete --name <rg-name> --yes --no-wait

# Check group deletion status
az group show --name <rg-name> --query properties.provisioningState -o tsv

# Get AKS credentials
az aks get-credentials --resource-group <rg> --name <cluster-name>
```

---

## Script Error Handling

All scripts use `set -e` at the top:

```bash
set -e
```

This means:
- **Exit on first error:** If any command fails, the script stops immediately
- **No silent failures:** You won't accidentally proceed with broken state

If a script fails:
1. Read the error message carefully
2. Fix the underlying issue
3. Re-run the script from the beginning (safe due to idempotent commands)

---

## Environment Variables

Most scripts support customization via environment variables:

```bash
# deploy.sh
RESOURCE_GROUP="rg-my-cluster" LOCATION="westus2" ./deploy.sh

# install-tools.sh
VCLUSTER_VERSION="v0.19.0" ./install-tools.sh
```

---

## Quick Reference — When to Use Each Script

| Goal | Script | Time |
|---|---|---|
| Set up demo environment | `deploy.sh` | 10 min |
| Install required tools | `install-tools.sh` | 5 min |
| Learn vcluster basics | `01-basic-vcluster/create-vcluster.sh` | 15 min |
| Explore multi-tenancy | `02-multi-tenant/setup-tenants.sh` | 15 min |
| Test resource limits | `03-resource-limits/setup-limits.sh` | 10 min |
| Understand sync | `04-custom-sync/setup-sync.sh` | 15 min |
| Expose via Ingress | `05-ingress-networking/setup-ingress.sh` | 20 min |
| Clean up everything | `cleanup.sh` | 10 min |

---

## Tips for Success

1. **Read the script before running** — Understand what it does
2. **Watch the output** — Each step prints progress; watch for errors
3. **Don't rush cleanup** — Run scripts in order; cleanup last
4. **Rerun if needed** — Most commands are idempotent; safe to re-run
5. **Check kubeconfig context** — Always know if you're on HOST or inside a vcluster
6. **Monitor Azure costs** — Clean up resource groups immediately after testing
