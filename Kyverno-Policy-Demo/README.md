# Kyverno Policy Demo on AKS

A hands-on demo for learning Kyverno — a Kubernetes-native policy engine. This demo provisions an AKS cluster via Terraform, installs Kyverno, and walks you through all four Kyverno policy types: **Validation**, **Mutation**, **Generation**, and **Cleanup**.

---

## What is Kyverno?

[Kyverno](https://kyverno.io) is a policy engine designed specifically for Kubernetes. Unlike OPA/Gatekeeper which requires Rego, Kyverno policies are written as Kubernetes resources (YAML), making them easy to read, write, and version-control.

Kyverno integrates with the Kubernetes Admission Webhook to:

| Policy Type    | What it does                                                                                  |
|----------------|-----------------------------------------------------------------------------------------------|
| **Validation** | Blocks non-compliant resources at admission time (or audits existing ones in background mode) |
| **Mutation**   | Automatically patches incoming resources to inject defaults or enforce standards              |
| **Generation** | Creates additional resources (e.g., NetworkPolicy, ResourceQuota) when a trigger fires        |
| **Cleanup**    | Periodically deletes resources that match specific conditions on a cron schedule              |

---

## Repository Structure

```
Kyverno-Policy-Demo/
├── deploy.sh                          # Full deployment script
├── cleanup.sh                         # Full teardown script
├── README.md                          # This file
├── POLICY-GUIDE.md                    # Manual policy deployment and verification guide
├── terraform/
│   ├── main.tf                        # Resource Group + modules wiring
│   ├── variables.tf                   # All input variables
│   ├── outputs.tf                     # Cluster name, RG, get-credentials command
│   ├── versions.tf                    # Provider version constraints
│   ├── terraform.tfvars.example       # Template — copy to terraform.tfvars
│   └── modules/
│       ├── aks/                       # AKS cluster module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── log_analytics/             # Log Analytics workspace module
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── policies/
│   ├── 01-validation/
│   │   ├── disallow-privileged-containers.yaml
│   │   ├── disallow-host-namespaces.yaml
│   │   ├── disallow-latest-tag.yaml
│   │   ├── require-pod-labels.yaml
│   │   └── require-resource-limits.yaml
│   ├── 02-mutation/
│   │   ├── add-default-labels.yaml
│   │   ├── add-default-resource-limits.yaml
│   │   └── add-security-context.yaml
│   ├── 03-generation/
│   │   ├── generate-default-network-policy.yaml
│   │   └── generate-namespace-resource-quota.yaml
│   └── 04-cleanup/
│       └── cleanup-completed-jobs.yaml
└── sample-apps/
    ├── 01-compliant-pod.yaml
    ├── 02-non-compliant-privileged.yaml
    ├── 03-non-compliant-no-limits.yaml
    ├── 04-non-compliant-latest-tag.yaml
    ├── 05-non-compliant-missing-labels.yaml
    ├── 06-mutation-test-pod.yaml
    ├── 07-generation-test-namespace.yaml
    ├── 08-cleanup-test-job.yaml
    └── test-policies.sh               # Interactive policy testing script
```

---

## Prerequisites

| Tool        | Minimum Version | Install                                                    |
|-------------|-----------------|------------------------------------------------------------|
| Azure CLI   | 2.60+           | [docs.microsoft.com/cli/azure](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform   | 1.6.0+          | [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/install) |
| kubectl     | 1.29+           | [kubernetes.io/docs](https://kubernetes.io/docs/tasks/tools/) |
| Helm        | 3.14+           | [helm.sh/docs](https://helm.sh/docs/intro/install/) |

---

## Quick Start

### 1. Authenticate with Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Configure Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred values
```

Key variables to review:

| Variable               | Default             | Description                                    |
|------------------------|---------------------|------------------------------------------------|
| `resource_group_name`  | `rg-kyverno-demo`   | Azure Resource Group name                      |
| `location`             | `northeurope`       | Azure region                                   |
| `cluster_name`         | `aks-kyverno-demo`  | AKS cluster name                               |
| `kubernetes_version`   | `1.32`              | AKS Kubernetes version                         |
| `node_vm_size`         | `Standard_D2s_v4`   | Node VM SKU                                    |
| `user_object_id`       | `""`                | Your Entra ID object ID for RBAC Cluster Admin |

To get your Entra ID object ID:
```bash
az ad signed-in-user show --query id -o tsv
```

### 3. Deploy everything

```bash
cd ..   # back to Kyverno-Policy-Demo/
./deploy.sh
```

The deploy script will:
1. Run `terraform init` and `terraform apply` to provision AKS + Log Analytics
2. Configure `kubectl` with AKS credentials
3. Install Kyverno via Helm (`kyverno/kyverno` chart)
4. Create the `demo` namespace

### 4. Deploy policies manually

Use the detailed policy guide in [POLICY-GUIDE.md](POLICY-GUIDE.md).

Quick apply commands:

```bash
kubectl apply -f policies/01-validation/
kubectl apply -f policies/02-mutation/
kubectl apply -f policies/03-generation/
kubectl apply -f policies/04-cleanup/
```

> **Tip:** You can override the Kyverno chart version:
> ```bash
> KYVERNO_CHART_VERSION=3.3.0 ./deploy.sh
> ```

---

## Running the Demo

### Automated test script

```bash
./sample-apps/test-policies.sh
```

This walks through all four policy types with clear PASS/FAIL output.

### Manual exploration

#### Section 1 — Validation Policies

These policies use `Enforce` mode, so violations are blocked immediately at admission.

**Test a compliant pod (should be allowed):**
```bash
kubectl apply -f sample-apps/01-compliant-pod.yaml
```

**Test a privileged container (should be blocked):**
```bash
kubectl apply -f sample-apps/02-non-compliant-privileged.yaml
# Expected error: "Privileged mode is disallowed."
```

**Test a pod with no resource limits (should be blocked):**
```bash
kubectl apply -f sample-apps/03-non-compliant-no-limits.yaml
# Expected error: "CPU and memory requests and limits are required."
```

**Test a pod with `:latest` tag (should be blocked):**
```bash
kubectl apply -f sample-apps/04-non-compliant-latest-tag.yaml
# Expected error: "Using the ':latest' image tag ... is not allowed."
```

**Test a pod with missing labels (should be blocked):**
```bash
kubectl apply -f sample-apps/05-non-compliant-missing-labels.yaml
# Expected error: "The labels 'app', 'version', and 'owner' are required."
```

#### Section 2 — Mutation Policies

Mutation policies silently modify resources as they are admitted. No error is thrown; instead, the resource is patched before being persisted.

**Apply the mutation test pod and inspect what Kyverno injected:**
```bash
kubectl apply -f sample-apps/06-mutation-test-pod.yaml

# Check the injected labels
kubectl get pod mutation-test -n demo -o jsonpath='{.metadata.labels}' | python3 -m json.tool

# Check the injected security context
kubectl get pod mutation-test -n demo \
  -o jsonpath='{.spec.containers[0].securityContext}' | python3 -m json.tool
```

Expected mutations:
- `metadata.labels.managed-by: kyverno` (added)
- `metadata.labels.environment: unknown` (added)
- `metadata.annotations["kyverno.io/mutated"]: "true"` (added)
- `spec.containers[0].securityContext.allowPrivilegeEscalation: false` (injected)
- `spec.containers[0].securityContext.runAsNonRoot: true` (injected)

#### Section 3 — Generation Policies

Generation policies trigger when a watched resource is created, automatically creating additional resources.

**Create a new namespace and observe generated resources:**
```bash
kubectl apply -f sample-apps/07-generation-test-namespace.yaml

# Kyverno generates NetworkPolicies and a ResourceQuota
kubectl get networkpolicy -n kyverno-demo-ns
kubectl get resourcequota -n kyverno-demo-ns
```

Expected generated resources:
- `NetworkPolicy/default-deny-ingress` — blocks all ingress by default
- `NetworkPolicy/allow-dns-egress` — allows DNS (port 53) egress only
- `ResourceQuota/default-quota` — caps CPU, memory, and Pod count

**Try deleting a generated resource — Kyverno re-creates it (synchronize=true):**
```bash
kubectl delete networkpolicy default-deny-ingress -n kyverno-demo-ns
# Wait 5-10 seconds
kubectl get networkpolicy default-deny-ingress -n kyverno-demo-ns  # re-created!
```

#### Section 4 — Cleanup Policies

Cleanup policies run on a cron schedule and delete resources matching the defined conditions.

**Deploy a Job that will complete quickly:**
```bash
kubectl apply -f sample-apps/08-cleanup-test-job.yaml

# Wait for it to complete
kubectl get job demo-completed-job -n demo -w

# The ClusterCleanupPolicy runs every 6 hours and will delete completed jobs.
# To see the cleanup policy:
kubectl describe clustercleanuppolicy cleanup-completed-jobs
```

---

## Policy Details

### Validation Policies

| Policy Name                       | Severity | Action  | Description                                          |
|-----------------------------------|----------|---------|------------------------------------------------------|
| `disallow-privileged-containers`  | High     | Enforce | Blocks pods that set `privileged: true`              |
| `disallow-host-namespaces`        | High     | Enforce | Blocks pods that use hostPID, hostIPC, or hostNetwork|
| `disallow-latest-tag`             | Medium   | Enforce | Blocks images tagged `:latest` or with no tag        |
| `require-resource-limits`         | Medium   | Enforce | Requires CPU and memory requests and limits          |
| `require-pod-labels`              | Low      | Enforce | Requires `app`, `version`, and `owner` labels        |

### Mutation Policies

| Policy Name                    | Description                                                                          |
|--------------------------------|--------------------------------------------------------------------------------------|
| `add-default-labels`           | Injects `managed-by=kyverno` and `environment=unknown` if not set                   |
| `add-security-context`         | Injects `allowPrivilegeEscalation=false` and `runAsNonRoot=true` if not set          |
| `add-default-resource-limits`  | Injects conservative CPU/memory requests and limits if not declared                  |

### Generation Policies

| Policy Name                         | Trigger      | Generated Resources                              |
|-------------------------------------|--------------|--------------------------------------------------|
| `generate-default-network-policy`   | New Namespace | `NetworkPolicy/default-deny-ingress`, `NetworkPolicy/allow-dns-egress` |
| `generate-namespace-resource-quota` | New Namespace | `ResourceQuota/default-quota`                    |

### Cleanup Policies

| Policy Name             | Schedule      | Condition                  | Action                 |
|-------------------------|---------------|----------------------------|------------------------|
| `cleanup-completed-jobs`| Every 6 hours | Job status = Complete      | Delete the Job         |

---

## Useful Commands

```bash
# List all ClusterPolicies and their statuses
kubectl get clusterpolicies

# Describe a specific policy (shows rules and status)
kubectl describe clusterpolicy disallow-privileged-containers

# View Kyverno admission controller logs (useful for debugging)
kubectl logs -n kyverno \
  -l app.kubernetes.io/name=kyverno-admission-controller \
  --tail=100 -f

# View background controller logs (for Generation & Cleanup)
kubectl logs -n kyverno \
  -l app.kubernetes.io/name=kyverno-background-controller \
  --tail=50

# View Policy Reports (background scan results for existing resources)
kubectl get policyreport -A
kubectl get clusterpolicyreport

# View detailed policy report for a namespace
kubectl describe policyreport -n demo

# Check admission webhook configuration
kubectl get validatingwebhookconfigurations | grep kyverno
kubectl get mutatingwebhookconfigurations | grep kyverno

# View policy violation events
kubectl get events -A --field-selector reason=PolicyViolation

# Dry-run test a manifest without applying it
kubectl apply -f sample-apps/02-non-compliant-privileged.yaml --dry-run=server
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Azure Resource Group: rg-kyverno-demo                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  AKS Cluster: aks-kyverno-demo                      │   │
│  │                                                     │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │  kyverno namespace                           │   │   │
│  │  │  ┌────────────────────────────────────────┐  │   │   │
│  │  │  │  Admission Controller (3 replicas)     │  │   │   │
│  │  │  │  Background Controller (2 replicas)    │  │   │   │
│  │  │  │  Cleanup Controller (2 replicas)       │  │   │   │
│  │  │  │  Reports Controller (2 replicas)       │  │   │   │
│  │  │  └────────────────────────────────────────┘  │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  │                                                     │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │  demo namespace                              │   │   │
│  │  │  • Sample pods and jobs for testing          │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  │                                                     │   │
│  │  Kubernetes Admission Webhook                       │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  kubectl apply ──► API Server ──► Kyverno      │ │   │
│  │  │      VALIDATE?  ──► Enforce/Audit              │ │   │
│  │  │      MUTATE?    ──► Patch & admit              │ │   │
│  │  │      GENERATE?  ──► Create child resources     │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Log Analytics Workspace: aks-kyverno-demo-law        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Kyverno Policy Concepts

### `validationFailureAction`

| Value    | Behaviour                                                    |
|----------|--------------------------------------------------------------|
| `Enforce`| Blocks the request immediately (hard enforcement)            |
| `Audit`  | Allows the request but records violations in Policy Reports  |

### `background: true`

When `background: true`, Kyverno scans existing resources periodically and generates Policy Reports for violations, even if they were created before the policy was applied.

### `synchronize: true` (Generation)

When `synchronize: true`, Kyverno keeps the generated resource in sync with the policy. If the generated resource is manually deleted or modified, Kyverno recreates/restores it.

### The `+()` operator (Mutation)

The `+(field)` syntax in mutation rules means **"add this field only if it does not already exist"**. This ensures mutations are non-destructive and respect explicitly set values.

### The `=()` operator (Validation)

The `=(field)` syntax means **"if this field exists, it must match the pattern"**. This is an optional field check — the policy only validates the field if it is present.

---

## Cleanup

To destroy all demo resources:

```bash
./cleanup.sh
```

This will:
1. Delete the `demo` and `kyverno-demo-ns` namespaces
2. Remove all Kyverno policies
3. Uninstall the Kyverno Helm release
4. Run `terraform destroy` to remove the AKS cluster and all Azure resources

---

## Further Reading

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kyverno Policy Library](https://kyverno.io/policies/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Kyverno CLI — Test policies locally](https://kyverno.io/docs/kyverno-cli/)
- [AKS Security Best Practices](https://learn.microsoft.com/azure/aks/operator-best-practices-cluster-security)
