# Enterprise GitHub Actions Runners on AKS Automatic

Run enterprise-scoped GitHub Actions container jobs on AKS Automatic with Actions Runner Controller, managed-disk workspaces and an Azure Files cache.

This experiment follows the AKS blog post
[GitHub Actions Runner Controller on AKS Automatic](https://blog.aks.azure.com/2026/09/17/github-actions-runner-controller-aks-automatic).
It provisions an AKS Automatic cluster and Azure Files storage with Terraform, then installs GitHub's
modern **runner scale set** Helm charts. It does not use legacy `RunnerDeployment`
resources, cert-manager, or GitHub webhook ingress. Following the Microsoft
Azure Files approach, **Kubernetes container mode** runs workflow jobs in separate
pods, with a per-runner managed disk workspace and a persistent Premium SMB NuGet cache.
There is no Docker daemon or privileged Docker-in-Docker (DinD) sidecar.
The primary walkthrough registers the runner scale set at **GitHub Enterprise
Cloud scope**, sharing it only with selected organizations and repositories.
Repository/organization registration remains available for smaller experiments.

## Architecture and defaults

```mermaid
flowchart TB
    github["GitHub Enterprise Cloud<br/>Selected organizations / repository job queues"]
    group["Enterprise runner group<br/>aks-enterprise-runners"]

    subgraph aks["Dedicated AKS Automatic cluster"]
        subgraph system["AKS-managed system nodes<br/>Deployment Safeguards enforced"]
            subgraph systemsNamespace["Namespace: arc-systems"]
                controller["ARC controller"]
                listener["Job listener"]
            end
        end

        subgraph runnerPool["Karpenter NodePool github-actions<br/>0-N nodes, Taint: workload=github-actions"]
            subgraph runnerPods["Namespace: arc-runners"]
                runners["0-5 ephemeral runner pods<br/>Kubernetes container hooks"]
                jobs["Workflow job pods<br/>Container image specified by workflow"]
            end
        end

        secret["Namespace: arc-runners<br/>Enterprise PAT authentication secret"]
        autoscaler["Node autoprovisioning (Karpenter)"]
        logs["Container Insights + control-plane logs"]
    end

    analytics["Log Analytics workspace"]
    workspaces["Per-runner workspace<br/>50 GiB managed disk (RWO)"]
    subgraph files["Azure Files: Premium_LRS storage account"]
        cache["Shared NuGet cache<br/>100 GiB persistent SMB share"]
    end

    listener -->|"Outbound HTTPS: poll for jobs"| github
    github -->|"Runner group access policy"| group
    group -.->|"Route authorized jobs"| listener
    runners -->|"Outbound HTTPS: execute jobs / report results"| github
    secret -.->|"Authenticate"| controller
    controller -->|"Manage runner lifecycle"| runners
    runners -->|"Create / exec / delete via Kubernetes API"| jobs
    runners -->|"Mount workspace"| workspaces
    jobs -->|"Mount same workspace"| workspaces
    jobs -->|"Restore packages / reuse cache"| cache
    listener -->|"Adjust desired runner count"| runners
    runners -.->|"Pending pods trigger node provisioning"| autoscaler
    autoscaler -->|"Create / consolidate VMs"| runnerPool
    controller -.-> logs
    listener -.-> logs
    runners -.-> logs
    jobs -.-> logs
    logs --> analytics
```

Namespace membership and node placement are shown separately: the authentication
secret is namespace-scoped, not assigned to a node pool. All GitHub connections
originate from the cluster; no incoming webhook is required.

| Decision | Demo configuration / rationale |
| ---------- | ------------------------------- |
| Cluster type | AKS Automatic (`azurerm_kubernetes_automatic_cluster`); AKS manages system nodes, upgrades, scaling and Safeguards |
| Node resource group | AKS-generated `MC_<rg>_<cluster>_<region>` (see note below) |
| Nodes | Karpenter `NodePool` `github-actions`: on-demand amd64 Linux D-family VMs with 2-8 vCPU, capped at 32 vCPU |
| Networking (Day 0) | AKS Automatic defaults: Azure CNI Overlay + Cilium, managed egress, no inbound application service |
| API access (Day 0) | Public endpoint restricted to your workstation/VPN IPv4 CIDRs |
| Azure access | Entra ID + Azure RBAC; local accounts disabled; deploying identity gets cluster admin |
| GitHub access | Enterprise PAT (classic), explicit enterprise runner group; optional App auth for repo/org scope |
| Scaling | ARC scales pods from queued jobs; node autoprovisioning creates/consolidates runner nodes from pending pods |
| Policy | Deployment Safeguards: every container sets requests/limits, images are pinned (no `latest`) |
| Container mode | Kubernetes hooks; every workflow job must specify `container:` |
| Storage | 50 GiB per-runner managed disk workspace (Azure Disk CSI, RWO), plus a persistent 100 GiB Azure Files NuGet cache |
| Storage authentication | Kubelet managed identity retrieves the cache SMB key; no account-key Kubernetes secret |
| Versions | ARC charts 0.15.0, runner 2.338.0; AzureRM ~> 5.9 |
| Observability | AKS Automatic managed monitoring plus diagnostic settings for API server and audit-admin logs |

**Why AKS Automatic?** As the blog post explains, Automatic removes node pool
sizing and autoscaler tuning: ARC creates runner pods, and node autoprovisioning
(Karpenter) picks a fitting VM size, then consolidates empty nodes after jobs
finish. Automatic also enables Azure RBAC with local accounts disabled, the
Azure Files CSI driver and the pod readiness SLA by default.

**Node resource group exception.** This repository normally sets an explicit
`rg-<project>-<env>-nodes` node resource group. AKS Automatic does not allow a
custom node resource group name, so Terraform reads the AKS-generated group from
`node_resource_group_id` and exposes it as the `node_resource_group_name` output.
Cleanup verifies that group is gone too.

**Runner NodePool.** `arc/runner-nodepool.yaml` defines a dedicated Karpenter
`NodePool` that labels nodes `workload=github-actions` and taints them
`workload=github-actions:NoSchedule`. Runner and job pods select and tolerate that
taint, so builds never land on system nodes. `limits.cpu: 32` caps total runner
capacity, and `consolidationPolicy: WhenEmptyOrUnderutilized` removes idle nodes.

The AKS-managed system nodes and listener stay running even when runners reach
zero. Runner nodes take a few minutes to provision on the first job.
`maxRunners: 5` is a runner cap; the NodePool `limits` are the node cap. Each
runner requests 250m CPU / 512 MiB; each job container requests 500m CPU / 1 GiB.
Service containers add further resources; tune limits accordingly.

This is **not a production configuration**. Production needs private API
connectivity (`private_cluster` or API server VNet integration with
`hosted_system`), controlled egress, durable log collection and tighter governance.
API/overlay CIDR choices affect later connectivity and should be planned before
provisioning. No Azure permissions are granted to jobs: use GitHub OIDC with a
separately scoped identity for any subsequent Azure deployment workflow.

## Prerequisites

- Azure subscription with permission to provision AKS and create role assignments
  (for example Contributor plus User Access Administrator).
- Terraform 1.9+, Azure CLI, `kubectl`, `kubelogin`, Helm with OCI support,
  `jq` (cleanup), and `openssl` (GitHub App authentication).
- A GitHub Enterprise Cloud account, an enterprise owner account for registration,
  and a private test repository in an allowed organization. Enterprise and
  organization policies must allow self-hosted runners. For repo/org-only
  experiments, runner administration permission on that scope is enough.
- A region that supports AKS Automatic (default `swedencentral`) and vCPU quota for
  the AKS-managed system nodes plus up to 32 vCPU of D-family runner nodes.
- Outbound access to GitHub, GHCR, MCR, NuGet and Azure endpoints, including
  node-level SMB TCP 445 access to Azure Files.
- AzureRM provider ~> 5.9 (for `azurerm_kubernetes_automatic_cluster`). AKS
  Automatic chooses and upgrades the Kubernetes version automatically.

## 1. Configure infrastructure

Run from this demo directory:

```bash
az login
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`. For simplicity, the demo leaves the AKS API
server reachable from any IP (`api_server_authorized_ip_ranges = []`); access is
still gated by Entra ID and Azure RBAC because AKS Automatic disables local
accounts.

> **Recommended practice:** restrict the API server to known egress IPs, even for
> demos. Set `api_server_authorized_ip_ranges = ["<your-public-ip>/32"]` (find it
> with `curl -s https://api.ipify.org`). Include every IP that runs `kubectl`/Helm
> against the cluster, such as your workstation, VPN or CI agents. Production
> clusters should go further and use a private API (see above).

Choose a region that supports AKS Automatic. There
are no node size or Kubernetes version variables: the runner NodePool controls
VM selection, and AKS Automatic manages the cluster version.

Terraform creates a dedicated `FileStorage` Premium_LRS account with a
`nuget-cache` SMB share. `cache_share_quota_gib` defaults to 100. The installer
creates a static RWX PV/PVC for this cache. The cache PV uses `Retain` and
survives ARC reinstalls, but **not a full Terraform destroy**.

Each runner gets its own generic ephemeral PVC: a 50 GiB `managed-csi` (Standard
SSD) Azure Disk, shared only with that runner's job/action pods and deleted with
the runner. The workspace is deliberately **not** on Azure Files: before every
job the Kubernetes hook copies the runner `externals` directory (~600 MB, ~9k
files) into the workspace, and that small-file copy over SMB takes many minutes.
A ReadWriteOnce disk works because the hook schedules job pods on the runner's
node. Use `managed-csi-premium` only if the NodePool is limited to `s` (premium
storage capable) VM sizes.

At mount time, kubelets use their identity (Storage Account Key Operator Service Role on this account)
to retrieve SMB keys. `storeAccountKey: "false"` avoids storing those keys in
Kubernetes Secrets; this is **not keyless SMB**. RBAC propagation may briefly
delay the first mount. The account uses an authenticated public storage endpoint
for the demo; production needs private endpoints/firewall rules and DNS design.

The scripts use your selected Azure CLI subscription unless `ARM_SUBSCRIPTION_ID`
is set. Terraform outputs record the subscription so subsequent Kubernetes access
and cleanup target the same cluster. Kubeconfig is isolated in `.kube/config`,
not merged into your normal kubeconfig.

## 2. Configure enterprise registration and access

Never paste credentials into Terraform variables, Helm values or committed files.
Do not run these scripts with shell tracing (`bash -x`).

### Enterprise runner group

1. As an enterprise owner, open your enterprise's **Policies -> Actions ->
   Runner groups** and create `aks-enterprise-runners`.
2. Set organization access to **Selected organizations** and allow only the
   organization containing your private test repository. Keep public repository
   access disabled.
3. In that organization's **Settings -> Actions -> Runner groups**, configure the
   inherited enterprise group to allow only the intended repositories. Enterprise
   organization access alone does **not** grant a repository access.
4. Optionally restrict the group to selected workflows, using the full
   `OWNER/REPO/.github/workflows/aks-runners-demo.yml@refs/heads/main` path (adjust
   the default branch). Only jobs directly defined in allowed workflows can use
   the group; review this when introducing reusable workflows.

The installer registers the scale set into an **existing** group. It does not
create groups or broaden access policies. Enterprise registration is a GitHub
scope setting; it does not make this one-system-node Azure cluster production HA.

### Enterprise authentication: PAT (classic)

Create a short-lived **personal access token (classic)** from an enterprise owner
account with **`manage_runners:enterprise`** scope (shown under `admin:enterprise`
in the token UI). Do not grant the broader enterprise administration scopes
unless separately needed. GitHub App and fine-grained PAT authentication are
not supported for this enterprise registration flow. Follow enterprise token/
SSO policies and use a dedicated, approved automation account where appropriate.

Use your enterprise **URL slug**, not its display name:

```bash
export GITHUB_CONFIG_URL="https://github.com/enterprises/YOUR-ENTERPRISE-SLUG"
export GITHUB_RUNNER_GROUP="aks-enterprise-runners"
export GITHUB_AUTH_MODE="pat"
printf "Enterprise runner PAT: "; read -rs GITHUB_PAT; echo
export GITHUB_PAT
```

The script rejects enterprise App authentication and missing runner groups
before provisioning. It cannot verify token scopes or enterprise access policies
locally; ARC registration and a workflow from an allowed repository are the
live verification steps. This example targets GitHub.com Enterprise Cloud;
GitHub Enterprise Server and enterprise-specific non-GitHub.com domains require
additional endpoint/TLS configuration and are outside this demo.

### Alternative: repository or organization GitHub App

Create and install a GitHub App on the account/organization owning the target:

- Repository scope: **Administration: Read and write**, **Metadata: Read-only**.
- Organization scope: **Self-hosted runners: Read and write**; repository
  Administration permission is unnecessary for organization registration.
- Install it on the intended repositories and download its private key **outside
  this repository**. The installation ID is not the App ID.

```bash
export GITHUB_CONFIG_URL="https://github.com/YOUR-OWNER/YOUR-REPOSITORY"
unset GITHUB_RUNNER_GROUP
export GITHUB_AUTH_MODE="app"
export GITHUB_APP_ID="123456"
export GITHUB_APP_INSTALLATION_ID="654321"
export GITHUB_APP_PRIVATE_KEY_FILE="$HOME/.config/github/arc-demo.pem"
```

For repository scope, unset `GITHUB_RUNNER_GROUP` because repository runners do
not use runner groups. For organization runners, use
`https://github.com/YOUR-ORG` and set `GITHUB_RUNNER_GROUP` to a pre-created
organization group assigned only to trusted repositories.

### Alternative: repository or organization PAT (classic)

Use a short-lived PAT (classic) with `repo` scope for repository runners or
`admin:org` for organization runners. The token's owner needs runner administration
permissions; authorize SSO if your organization requires it.

```bash
export GITHUB_CONFIG_URL="https://github.com/YOUR-OWNER/YOUR-REPOSITORY"
unset GITHUB_RUNNER_GROUP
export GITHUB_AUTH_MODE="pat"
printf "GitHub PAT: "; read -rs GITHUB_PAT; echo
export GITHUB_PAT
```

The installer reads secret material from files, pipes the Kubernetes Secret
directly into the API using server-side apply, and removes temporary files.
GitHub credentials are not passed in CLI literals, included in Helm release values,
or written to Terraform state. AzureRM storage account resources can
still record storage keys in Terraform state; secure the state accordingly.
The Kubernetes Secret remains sensitive: cluster administrators
can read it; restrict access and rotate it.

## 3. Deploy

```bash
bash deploy.sh
```

The script validates prerequisites/configuration, initializes and validates
Terraform, shows a saved plan, and asks for `yes` before creating billable
resources. It then obtains Entra credentials (Azure Kubernetes Service RBAC
Cluster Admin through `kubelogin`), waits for RBAC propagation, installs
both pinned charts and waits for the listener to be ready.
It also applies the runner Karpenter NodePool, the cache PV/PVC, workspace
StorageClass and job-hook ConfigMap. Runner namespaces enforce **baseline** Pod Security admission,
not privileged admission.

For subsequent ARC configuration changes or authentication rotation:

```bash
bash scripts/install-arc.sh
```

Use the same authentication mode when rotating. Switching App/PAT authentication
requires replacing the existing `github-auth` secret to avoid retaining old
credential keys. Do this only after draining jobs, then reinstall ARC. Chart
upgrades can require CRD updates; read upstream release notes before changing
`ARC_VERSION` in `scripts/common.sh`. Keep both charts on the same version.
GitHub requires runner software to remain current; refresh the image pins
regularly rather than leaving this demo unattended indefinitely.

### Migrating a previously deployed DinD version

Drain jobs and uninstall the existing `aks-arc-runners` release while leaving the
controller running before deploying this revision. This changes service-account
permissions, workspace volumes and job execution behavior, so do not migrate
active runners in place. Remove any network policies from earlier revisions after draining:

```bash
export KUBECONFIG="$PWD/.kube/config"
helm uninstall aks-arc-runners -n arc-runners --wait --timeout 15m
kubectl delete networkpolicy runner-egress -n arc-runners --ignore-not-found
kubectl delete ciliumnetworkpolicy runner-egress job-egress -n arc-runners --ignore-not-found
bash deploy.sh
```

Workflows must be
updated to use `container:` before submitting jobs to the new runner set.

## 4. Run the smoke and scaling workflow

Copy `workflows/aks-runners-demo.yml` to
`.github/workflows/aks-runners-demo.yml` **in a private repository allowed by the
enterprise runner group** (or the configured repository for repository scope).
Commit it and make it available on that repository's default branch for manual
dispatch. It is deliberately not installed as an active workflow in this repo.

Open **Actions -> AKS ARC Azure Files demo -> Run workflow**. Five matrix jobs
target `runs-on: aks-arc-runners`, run inside .NET SDK job containers, restore
Newtonsoft.Json into `/nuget/packages`, build/run a console app and pause for one
minute. Persistent markers under `/nuget/demo-markers` show cache continuity
across subsequent workflow runs. With ARC, use the scale set name, not
`[self-hosted, linux, x64]`.
The hook sets both `NUGET_PACKAGES=/nuget/packages` and
`NUGET_SCRATCH=/nuget/scratch` on the same share so concurrent restores coordinate
NuGet filesystem locks rather than using independent per-pod scratch directories.
The same workflow works across allowed organizations: registration remains at
enterprise scope, while workflows always live in repositories. Use a unique
scale set name within the accessible groups to avoid ambiguous routing.

Check **Enterprise -> Policies -> Actions -> Runners / Runner groups** for the
scale set, then dispatch the workflow from an allowed repository. Confirm it
finishes on the AKS runners. A repository not allowed by the inherited group must
not be able to use these runners; its job may remain queued rather than produce
an immediate error. Check enterprise **and** organization/repository policy when
diagnosing queued jobs.

```bash
export KUBECONFIG="$PWD/.kube/config"
kubectl get pods -n arc-runners -w
# In another terminal with the same KUBECONFIG:
kubectl get nodes -L workload,karpenter.sh/nodepool,node.kubernetes.io/instance-type -w
kubectl get nodepools.karpenter.sh github-actions
kubectl get nodeclaims.karpenter.sh
kubectl get pods -n arc-systems
kubectl get autoscalingrunnersets.actions.github.com -n arc-runners
kubectl get pvc -n arc-runners
kubectl get pv
```

Expected: listener remains on AKS-managed system nodes; Karpenter creates
`NodeClaims` for the `github-actions` NodePool; ephemeral runners land only on
those nodes along with their job pods, complete one job each, then disappear.
Per-runner PVCs/shares are deleted after their owning pods are removed; the
`nuget-cache` PVC/share remains. About two minutes after the last job,
consolidation removes the empty runner nodes. No checkout step is needed for this
smoke test; the standard runner image is not a full `ubuntu-latest` VM, so install
your build tools in the workflow's job image for real projects.

### Container-mode limitations

Every job requires `container:`; the chart injects
`ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=true`. Image-based container actions can
use the hooks, but Dockerfile-based actions and direct `docker build` commands
are not supported by this configuration. Use a separately reviewed image-build
solution if needed. Docker `container.options` are not generally supported by
the hooks. Shared NuGet caches are only for jobs within the same trust boundary:
untrusted jobs could poison packages for subsequent builds.

## Security boundaries

- **Only trusted code.** Do not attach these runners to untrusted fork PRs or
  public PR workflows. Manual dispatch alone is not a boundary if other
  workflows can select the runner set. Limit runner group/repository access.
- All organizations using this scale set share its cache and runner credentials.
  Use separate scale sets, namespaces, storage and appropriately scoped credentials
  for different trust boundaries; enterprise registration is not tenant isolation.
- No DinD or privileged containers are configured. Dedicated pools/namespaces
  are still **not** a hard security boundary; keep this cluster separate from
  production workloads.
- Runner hooks need mounted service-account tokens and namespace-scoped
  permissions to create/exec/delete pods and read/create/delete secrets.
  This includes access to the GitHub credential secret in `arc-runners`:
  Kubernetes mode is **not safe for untrusted code**. Job pods do not mount
  service-account tokens; the hook template applies placement and resource limits.
- To keep the demo simple, no network policies are applied. For production,
  add Cilium egress policies for runner and job pods. Allow the Kubernetes API
  (runner pods only), DNS and GitHub/registry HTTPS. AKS Automatic enables
  LocalDNS, so pods resolve via node-local `169.254.10.10/11`. DNS rules must
  allow that address (for example `toEntities: [host]`), not just `kube-dns`
  endpoints, or runners can't reach GitHub.
- No node Docker socket or host filesystem is mounted.
- Pin actions to reviewed commit SHAs in real workflows. Grant job tokens only
  the minimum permissions and use OIDC rather than long-lived Azure credentials.
- Logs can contain workflow secrets; restrict Log Analytics access and configure
  appropriate retention/export. Container Insights is not a guarantee of
  lossless log retention from short-lived pods.
- Terraform local state contains sensitive cluster metadata and may contain
  storage keys even though GitHub credentials are excluded. Never commit it; use a secured remote backend
  for anything beyond this local demo.

## Troubleshooting

| Symptom | Checks |
| --------- | -------- |
| `AKSCapacityHeavyUsage` / `SkuNotAvailable` on create | Managed system node pools are capacity-restricted in that region. Delete the failed cluster/resource group, set another AKS Automatic region in `terraform.tfvars`, and check `az vm list-skus -l REGION --size Standard_D4lds_v5 --query "[].restrictions"` returns empty lists |
| API timeout / forbidden | Verify public egress CIDR, tenant/login, target subscription, deployer RBAC propagation and `kubelogin` |
| `failed to fetch oauth token ... ghcr.io ... 403 Forbidden` on `helm upgrade --install` | The ARC charts are public; Helm is sending a stale/expired GHCR credential from your keychain. Run `helm registry logout ghcr.io` and `docker logout ghcr.io`, then re-run `deploy.sh` |
| Helm chart pull 403 / image pull failure | Check GHCR/Docker Hub access, proxy/firewall policies and registry authentication; do not disable TLS verification |
| Listener fails / 401 / 403 | Inspect controller/listener logs; verify App installation ID, permissions, repository access, PAT expiry and organization policies |
| Enterprise registration fails | Enterprise slug; PAT classic with `manage_runners:enterprise`; enterprise-owner account; existing enterprise group; token/SSO policies |
| Jobs remain queued | Exact `runs-on` name; correct GitHub URL; runner group access; ready listener |
| Runner pods Pending | `kubectl describe nodepool github-actions`, NodeClaim events, D-family vCPU quota, NodePool `limits`, labels/taints and resource requests |
| Admission denied by Safeguards | Every container needs CPU/memory requests and limits; images must use a pinned tag, not `latest`. Check `kubectl get events` for the policy name |
| Runner deprecated / cannot receive messages | Runner image too old: bump `ghcr.io/actions/actions-runner` in `arc/runner-values.yaml` and reinstall |
| Workspace PVC or mount failure | Files CSI enabled; storage RBAC propagation; node TCP 445; quota and Premium share size; inspect PVC/pod events |
| Jobs sit at **Initialize containers** for many minutes | The work volume is on Azure Files: SMB copies ~600 MB of runner `externals` per job. Confirm `kubernetesModeWorkVolumeClaim` uses `managed-csi` (RWO) and `kubectl get pvc -n arc-runners` shows disk-backed PVCs |
| Container job stays Pending | Hook template ConfigMap, runner-pool taint toleration, amd64 images, requests/limits and workspace/cache PVCs |
| Missing job container / Docker error | Add `container:` to every job; this mode has no Docker daemon |
| Nodes do not scale down immediately | `consolidateAfter` delay, active jobs, PVC detach and other pods; AKS-managed system nodes intentionally stay running |

```bash
kubectl logs -n arc-systems deployment/arc-controller --tail=100
kubectl logs -n arc-systems -l app.kubernetes.io/component=runner-scale-set-listener --tail=100
kubectl get pods -n arc-runners
kubectl get events -n arc-runners --sort-by=.lastTimestamp
# Substitute names from the pod listing:
kubectl logs -n arc-systems LISTENER-POD --tail=100
kubectl logs -n arc-runners RUNNER-POD -c runner --tail=100
kubectl describe pvc -n arc-runners nuget-cache
```

## Cleanup and cost

AKS Automatic uses the **Standard** control-plane tier (billed per cluster hour)
plus AKS-managed system nodes, runner nodes, load balancer/public IP, outbound
traffic and Log Analytics.
The 100 GiB Premium cache is billed even with zero runners. Each active runner
provisions another **50 GiB managed disk**, deleted with the runner pod; verify
no `pvc-*` disks remain in the node resource group after runs. ARC removal alone does not delete the persistent cache.
Do not leave the demo running unnecessarily.

Stop workflow submissions and wait for jobs to finish, then:

```bash
bash cleanup.sh
unset GITHUB_PAT
```

Cleanup requires the local Terraform state and original infrastructure variables.
It confirms the target, uninstalls the runner scale set **before** the controller
so GitHub registrations can be removed, deletes the runner NodePool so Karpenter
drains its nodes, destroys all Terraform resources
(including the entire storage account, cache and any remaining workspace disks in the node resource group), verifies
both the demo and AKS-generated node resource groups are gone, then removes local state/backups, saved plan,
provider cache, lockfile and isolated kubeconfig. If an operation fails, state is
retained: resolve the error and rerun. If the cluster was manually deleted, the
script skips Helm but still destroys the remaining Terraform resources; remove
stale GitHub runners manually if necessary. Revoke the PAT or uninstall the App
when finished. Do not delete state before a successful destroy.

## Local validation (no deployment)

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
terraform -chdir=terraform test
bash tests/test-scripts.sh
shellcheck -S warning -e SC2034,SC2046,SC2207 deploy.sh cleanup.sh scripts/*.sh tests/*.sh
yamllint -d '{extends: relaxed, rules: {line-length: {max: 200}}}' arc workflows
```

## References

- [GitHub: deploying runner scale sets](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets)
- [GitHub: authenticating ARC](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api)
- [GitHub Enterprise Cloud: runner group access policies](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/manage-runners/self-hosted-runners/manage-access)
- [GitHub Enterprise Cloud: self-hosted runner API and token scopes](https://docs.github.com/en/enterprise-cloud@latest/rest/actions/self-hosted-runners#create-a-registration-token-for-an-enterprise)
- [ARC chart configuration](https://github.com/actions/actions-runner-controller/tree/gha-runner-scale-set-0.15.0/charts)
- [Microsoft: GitHub Actions on AKS overview](https://learn.microsoft.com/en-us/azure/aks/github-actions-azure-files-overview)
- [Microsoft: create ARC infrastructure with Azure Files](https://learn.microsoft.com/en-us/azure/aks/github-actions-azure-files-create-infrastructure)
- [Azure Files CSI driver parameters](https://github.com/kubernetes-sigs/azurefile-csi-driver/blob/master/docs/driver-parameters.md)
- [GitHub Kubernetes container hook limitations](https://github.com/actions/runner-container-hooks/blob/main/packages/k8s/README.md)
- [AKS blog: GitHub Actions Runner Controller on AKS Automatic](https://blog.aks.azure.com/2026/09/17/github-actions-runner-controller-aks-automatic)
- [Microsoft: AKS Automatic overview](https://learn.microsoft.com/en-us/azure/aks/intro-aks-automatic)
- [Microsoft: node autoprovisioning NodePools](https://learn.microsoft.com/en-us/azure/aks/node-autoprovision-node-pools)
- [AzureRM AKS Automatic resource reference](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_automatic_cluster)

This demo adapts the Microsoft Azure Files/Kubernetes-mode storage pattern (keeping
Azure Files for the shared cache but using managed disks for workspaces),
using Terraform rather than Azure CLI for provisioning. It keeps pinned ARC
versions, a dedicated Karpenter NodePool and a small dev/test cluster; it does not claim
the high availability suggested by the reference architecture's title.
