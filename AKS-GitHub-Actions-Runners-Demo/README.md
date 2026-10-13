# GitHub Actions Runners on AKS

Run ephemeral, autoscaling GitHub Actions runners on a dedicated AKS cluster using Actions Runner Controller.

This experiment provisions Azure resources with Terraform, then installs GitHub's
modern **runner scale set** Helm charts. It does not use legacy `RunnerDeployment`
resources, cert-manager, or GitHub webhook ingress. Docker builds and container
actions run through a **privileged Docker-in-Docker (DinD)** sidecar.

## Architecture and defaults

```text
GitHub repository/organization job queue
                 |
                 | outbound HTTPS (no incoming webhook)
                 v
Dedicated AKS cluster
  system pool: 1 node, CriticalAddonsOnly taint
    arc-systems: ARC controller + listener
    arc-runners: GitHub authentication secret
  runner pool: 0-3 nodes, workload=github-actions taint
    arc-runners: 0-5 ephemeral runner pods + DinD
                 |
                 v
Container Insights + control-plane logs -> Log Analytics
```

| Decision | Demo configuration / rationale |
|----------|-------------------------------|
| Cluster type | AKS Standard, Free tier; explicit pools and cluster autoscaler rather than AKS Automatic/NAP |
| Node resource group | `rg-gha-runners-dev-nodes`, explicitly named and managed by AKS |
| Nodes | Azure Linux 3, x86-64 `Standard_D4as_v5`; one persistent system node |
| Networking (Day 0) | Azure CNI Overlay + Cilium, standard load balancer egress, no inbound application service |
| API access (Day 0) | Public endpoint restricted to your workstation/VPN IPv4 CIDRs |
| Azure access | Entra ID + Azure RBAC; local accounts disabled; deploying identity gets cluster admin |
| GitHub access | GitHub App recommended; PAT (classic) supported for quick experiments |
| Scaling | ARC scales pods from queued jobs; AKS scales runner nodes from pending pods |
| Storage | Ephemeral `emptyDir` workspaces and Docker data; no shared cache or persistent volumes |
| Versions | ARC charts 0.15.0, runner 2.338.0, DinD 29.9.0; AzureRM ~> 5.9 |
| Observability | Container Insights; API server, audit-admin and cluster-autoscaler logs |

The system pool and listener stay running even when runners reach zero. Runner
nodes take several minutes to provision on the first job. `maxRunners: 5` is a
runner cap, **not** a node cap. Each runner requests 1 CPU and 2 GiB total for the
runner and Docker sidecar; tune this and the node limit for your workload.

This is **not a production/high-availability configuration**. Production needs
multiple system nodes, zone redundancy, a paid control-plane tier, private API
connectivity, controlled egress, durable log collection and tighter governance.
API/overlay CIDR choices affect later connectivity and should be planned before
provisioning. No Azure permissions are granted to jobs: use GitHub OIDC with a
separately scoped identity for any subsequent Azure deployment workflow.

## Prerequisites

- Azure subscription with permission to provision AKS and create role assignments
  (for example Contributor plus User Access Administrator).
- Terraform 1.9+, Azure CLI, `kubectl`, `kubelogin`, Helm with OCI support,
  `jq` (cleanup), and `openssl` (GitHub App authentication).
- A trusted GitHub repository or organization where you can administer runners.
  Prefer a private test repository. Organization policies must allow self-hosted runners.
- Enough regional quota for the system node, up to three runner nodes, and upgrade
  surge nodes. Choose another supported non-burstable **amd64** VM size if needed.
- Outbound access to GitHub, GHCR, Docker Hub and Azure endpoints.
- A currently supported AKS Kubernetes version >= 1.29 (native sidecars required).

## 1. Configure infrastructure

Run from this demo directory:

```bash
az login
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`. Replace `203.0.113.10/32` with your
workstation/VPN's real public egress IPv4 CIDR. Terraform rejects the placeholder
and unrestricted `0.0.0.0/0`. Choose region and node size as appropriate. Leave
`kubernetes_version` unset to use AKS's recommended version.

The scripts use your selected Azure CLI subscription unless `ARM_SUBSCRIPTION_ID`
is set. Terraform outputs record the subscription so subsequent Kubernetes access
and cleanup target the same cluster. Kubeconfig is isolated in `.kube/config`,
not merged into your normal kubeconfig.

## 2. Configure GitHub authentication

Never paste credentials into Terraform variables, Helm values or committed files.
Do not run these scripts with shell tracing (`bash -x`).

### Recommended: GitHub App

Create and install a GitHub App on the account/organization owning the target:

- Repository scope: **Administration: Read and write**, **Metadata: Read-only**.
- Organization scope: **Self-hosted runners: Read and write**; repository
  Administration permission is unnecessary for organization registration.
- Install it on the intended repositories and download its private key **outside
  this repository**. The installation ID is not the App ID.

```bash
export GITHUB_CONFIG_URL="https://github.com/YOUR-OWNER/YOUR-REPOSITORY"
export GITHUB_AUTH_MODE="app"
export GITHUB_APP_ID="123456"
export GITHUB_APP_INSTALLATION_ID="654321"
export GITHUB_APP_PRIVATE_KEY_FILE="$HOME/.config/github/arc-demo.pem"
```

For organization runners, use `https://github.com/YOUR-ORG`, and restrict access
using an organization runner group (`runnerGroup` in the runner values) assigned
only to trusted repositories. Enterprise scope and GitHub Enterprise Server are
outside this demo's scope.

### Quick experiment: personal access token (classic)

Use a short-lived PAT (classic) with `repo` scope for repository runners or
`admin:org` for organization runners. The token's owner needs runner administration
permissions; authorize SSO if your organization requires it.

```bash
export GITHUB_CONFIG_URL="https://github.com/YOUR-OWNER/YOUR-REPOSITORY"
export GITHUB_AUTH_MODE="pat"
read -r -s -p "GitHub PAT: " GITHUB_PAT; echo
export GITHUB_PAT
```

The installer reads secret material from files, pipes the Kubernetes Secret
directly into the API using server-side apply, and removes temporary files.
Credentials are not passed in CLI literals or included in Helm release values or
Terraform state. The Kubernetes Secret remains sensitive: cluster administrators
can read it; restrict access and rotate it.

## 3. Deploy

```bash
bash deploy.sh
```

The script validates prerequisites/configuration, initializes and validates
Terraform, shows a saved plan, and asks for `yes` before creating billable
resources. It then obtains Entra credentials, waits for RBAC propagation, installs
both pinned charts and waits for the listener to be ready.

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

## 4. Run the smoke and scaling workflow

Copy `workflows/aks-runners-demo.yml` to
`.github/workflows/aks-runners-demo.yml` **in the repository configured above**.
Commit it and make it available on that repository's default branch for manual
dispatch. It is deliberately not installed as an active workflow in this repo.

Open **Actions -> AKS ARC runner demo -> Run workflow**. Five matrix jobs target
`runs-on: aks-arc-runners`, verify Docker, build/run a small container and pause
for one minute so you can observe scaling. With ARC, use the scale set name, not
`[self-hosted, linux, x64]`.

```bash
export KUBECONFIG="$PWD/.kube/config"
kubectl get pods -n arc-runners -w
# In another terminal with the same KUBECONFIG:
kubectl get nodes -L workload -w
kubectl get pods -n arc-systems
kubectl get autoscalingrunnersets.actions.github.com -n arc-runners
```

Expected: listener remains on the system pool; ephemeral runners land only on
the runner pool, complete one job each, then disappear. After the autoscaler
idle delay, runner nodes return to zero. No checkout step is needed for this
smoke test; the standard runner image is not a full `ubuntu-latest` VM, so install
your build tools or build a custom runner image for real projects.

## Security boundaries

- **Only trusted code.** Do not attach these runners to untrusted fork PRs or
  public PR workflows. Manual dispatch alone is not a boundary if other
  workflows can select the runner set. Limit runner group/repository access.
- DinD is privileged and can compromise its node. Dedicated pools/namespaces
  are scheduling separation, **not** a hard security boundary. Keep this
  dedicated cluster separate from application/production workloads.
- Runner service-account tokens are not mounted. The egress policy permits
  public HTTP/HTTPS and cluster DNS, denying ingress and ordinary private/
  link-local egress. Privileged code can circumvent pod-level controls; this is
  defense in depth, not sandboxing. Do not grant the node identity access to
  production secrets. Private registries need a deliberately scoped policy change.
- The listener needs Kubernetes access and is intentionally not selected by
  the runner egress policy. No node Docker socket or host filesystem is mounted.
- Pin actions to reviewed commit SHAs in real workflows. Grant job tokens only
  the minimum permissions and use OIDC rather than long-lived Azure credentials.
- Logs can contain workflow secrets; restrict Log Analytics access and configure
  appropriate retention/export. Container Insights is not a guarantee of
  lossless log retention from short-lived pods.
- Terraform local state still contains sensitive cluster metadata even though
  GitHub credentials are excluded. Never commit it; use a secured remote backend
  for anything beyond this local demo.

## Troubleshooting

| Symptom | Checks |
|---------|--------|
| API timeout / forbidden | Verify public egress CIDR, tenant/login, target subscription, deployer RBAC propagation and `kubelogin` |
| Helm chart pull 403 / image pull failure | Check GHCR/Docker Hub access, proxy/firewall policies and registry authentication; do not disable TLS verification |
| Listener fails / 401 / 403 | Inspect controller/listener logs; verify App installation ID, permissions, repository access, PAT expiry and organization policies |
| Jobs remain queued | Exact `runs-on` name; correct GitHub URL; runner group access; ready listener |
| Runner pods Pending | Runner node quota/capacity, autoscaler events, labels/taints, amd64 node size and resource requests |
| Docker startup failure | Kubernetes >= 1.29, privileged admission, image pull access, disk capacity and DinD startup probe |
| Nodes do not scale down immediately | Autoscaler idle delay, active jobs and other pods; system pool intentionally stays running |

```bash
kubectl logs -n arc-systems deployment/arc-controller --tail=100
kubectl get pods -n arc-runners
kubectl get events -n arc-runners --sort-by=.lastTimestamp
# Substitute names from the pod listing:
kubectl logs -n arc-systems LISTENER-POD --tail=100
kubectl logs -n arc-runners RUNNER-POD -c dind --tail=100
```

## Cleanup and cost

AKS Free tier does **not** mean free nodes. System compute/disks, runner nodes,
load balancer/public IP, outbound traffic and Log Analytics incur charges.
Do not leave the demo running unnecessarily.

Stop workflow submissions and wait for jobs to finish, then:

```bash
bash cleanup.sh
unset GITHUB_PAT
```

Cleanup requires the local Terraform state and original infrastructure variables.
It confirms the target, uninstalls the runner scale set **before** the controller
so GitHub registrations can be removed, destroys all Terraform resources, verifies
both resource groups are gone, then removes local state/backups, saved plan,
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
- [ARC chart configuration](https://github.com/actions/actions-runner-controller/tree/gha-runner-scale-set-0.15.0/charts)
- [Microsoft: GitHub Actions on AKS overview](https://learn.microsoft.com/en-us/azure/aks/github-actions-azure-files-overview)
- [AzureRM AKS resource reference](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster)

The Microsoft reference uses Azure Files and Kubernetes container mode. This
demo intentionally uses ephemeral storage and DinD instead, following GitHub's
runner scale set templates.
