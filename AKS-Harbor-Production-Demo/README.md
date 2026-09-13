# Harbor on AKS — Production Architecture (Terraform Modules + Traefik + cert-manager + Entra ID SSO)

A production-shaped Harbor container registry deployment on AKS: private networking, an
external PostgreSQL Flexible Server and Azure Cache for Redis Premium, Key Vault-backed
secrets synced via the Secrets Store CSI driver, Microsoft Entra ID OIDC login with
per-role security groups, and Azure Monitor + Managed Grafana observability — all
provisioned through composable Terraform modules.

It is the production-oriented companion to the simpler [AKS-Harbor-Registry-Demo](../AKS-Harbor-Registry-Demo),
which uses Harbor's bundled internal Postgres/Redis and local auth only. Use this demo
when you want to see what a hardened, defense-in-depth Harbor deployment looks like end
to end.

## 📋 Overview

| Concern | How it's covered |
|---|---|
| Container registry | Harbor Helm chart with **external** PostgreSQL Flexible Server + Azure Cache for Redis Premium (no bundled DB/cache), Azure Files Premium ZRS NFS for registry storage |
| Networking | Dedicated VNet with delegated subnets for AKS, PostgreSQL, and Private Link, plus private DNS zones for PostgreSQL, Redis, and Key Vault |
| Secrets | Azure Key Vault (RBAC, private endpoint, purge protection) — synced into Kubernetes Secrets via the AKS-managed Secrets Store CSI driver (Workload Identity, no stored credentials) |
| Ingress | [Traefik](https://traefik.io/traefik) (Helm) + `IngressRoute`/`Middleware` — HTTPS with HTTP→HTTPS redirect and HSTS, mirroring the registry demo's proven pattern |
| TLS | cert-manager `Certificate` (`harbor-tls`) issued by a Let's Encrypt production `ClusterIssuer` via **Azure DNS DNS-01**, authenticated with Azure Workload Identity (no client secret) |
| Audit logs | Fluent Bit sidecar (`harbor-audit-forwarder`) re-emits Harbor's audit syslog stream to stdout → Container Insights → Log Analytics `ContainerLogV2`. **Must be `Ready` before Harbor installs** — `harbor-core` dials it at startup and exits if unreachable |
| Metrics | Harbor Prometheus metrics → Azure Monitor managed Prometheus (DCE/DCR) → Azure Managed Grafana |
| SSO | Microsoft Entra ID OIDC login — app registration/SPN + client secret + 6 Harbor role groups, fully Terraform-managed in `modules/identity` (see [Microsoft Entra ID OIDC SSO](#-microsoft-entra-id-oidc-sso)) |
| Node pools | Dedicated `system` and `harbor` node pools, both zone-redundant and autoscaling |

## 🏗️ Architecture

```mermaid
flowchart TB
    subgraph AKS["AKS Cluster (private VNet)"]
        Traefik["Traefik\n(LoadBalancer)"]
        CertManager["cert-manager\n(Workload Identity)"]
        Forwarder["harbor-audit-forwarder\n(Fluent Bit)"]
        HarborCore["harbor-core"]
        HarborSvc["Harbor components\n(registry, jobservice, portal, trivy)"]
        CSI["Secrets Store CSI\n(Key Vault provider)"]
    end

    subgraph Data["Private data plane"]
        PG[("PostgreSQL\nFlexible Server\n(zone-redundant HA)")]
        Redis[("Azure Cache\nfor Redis Premium")]
        KV[("Key Vault\n(private endpoint)")]
    end

    Internet(("Client / Browser")) -->|HTTPS| Traefik
    Traefik --> HarborCore
    HarborCore --> HarborSvc
    HarborSvc -->|private endpoint| PG
    HarborSvc -->|private endpoint| Redis
    CSI -->|private endpoint| KV
    HarborCore -->|TCP syslog :10514| Forwarder
    Forwarder -->|stdout| LAW[("Log Analytics\nContainerLogV2")]
    HarborSvc -->|/metrics| AMW[("Azure Monitor\nWorkspace")]
    AMW --> Grafana[("Azure Managed\nGrafana")]

    CertManager -->|DNS-01| AzureDNS[("Azure DNS Zone\n(existing)")]

    EntraID[("Microsoft Entra ID\napp + 6 role groups")] -.->|OIDC login| HarborCore
```

## 📁 Contents

```text
AKS-Harbor-Production-Demo/
├── deploy.sh
├── cleanup.sh
├── terraform/
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf                 # wires every module below via `module` blocks
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── network/            # VNet, delegated subnets, private DNS zones
│       ├── aks/                # AKS cluster + harbor node pool + Key Vault CSI
│       ├── identity/           # cert-manager Workload Identity + Entra ID OIDC/SSO
│       ├── postgres/           # PostgreSQL Flexible Server (private, zone-redundant)
│       ├── redis/               # Azure Cache for Redis Premium (private endpoint)
│       ├── keyvault/            # Key Vault + all Harbor secrets
│       └── alerts/              # variables only today — not yet wired into main.tf
└── kubernetes-manifests/
    ├── namespace.yaml
    ├── cluster-issuer.yaml.tpl          # cert-manager ClusterIssuer (envsubst template)
    ├── audit-log-forwarder.yaml         # Fluent Bit ConfigMap+Deployment+Service
    ├── secretproviderclass.yaml.tpl     # Key Vault CSI SecretProviderClass
    ├── keyvault-secret-sync.yaml        # forces the CSI driver to materialize K8s Secrets
    ├── storageclass-azurefile-zrs-nfs.yaml
    ├── harbor-values.yaml.tpl           # Harbor Helm values (envsubst template)
    ├── harbor-certificate.yaml.tpl      # cert-manager Certificate
    └── harbor-ingress-route.yaml.tpl    # Traefik IngressRoute + Middleware
```

Every module under `terraform/modules/` (except `alerts`, which is only a
`variables.tf` stub) is wired into the root `main.tf` via `module` blocks —
`terraform apply` provisions the full architecture described above, not just
the AKS cluster.

## ✅ Prerequisites

- Azure CLI (`az`) logged in with Contributor + User Access Administrator (or equivalent) on the target subscription
- An **existing** Azure DNS zone already delegated to Azure DNS (this demo reads it as a data source; it does not create or delegate a zone)
- Microsoft Entra ID permissions to create app registrations, create/manage security groups, and grant admin consent — only required while `enable_oidc_auth = true` (the default)
- Terraform >= 1.6.0
- `kubectl`, `helm` (>= 3.8), `envsubst` (part of `gettext`)

## 🚀 Quick Start

```bash
cd AKS-Harbor-Production-Demo/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: dns_zone_name, dns_zone_resource_group, acme_email
cd ..
./deploy.sh
```

`deploy.sh` runs, in order:
1. `terraform apply` — resource group, VNet + subnets + private DNS zones, AKS (Workload Identity + OIDC issuer, Container Insights, managed Prometheus, Key Vault Secrets Provider), the cert-manager identity + federated credential + DNS role assignment, PostgreSQL Flexible Server, Redis Premium, Key Vault with all Harbor secrets, Azure Managed Grafana, and (if `enable_oidc_auth = true`) the Entra ID app/SPN, client secret, and 6 Harbor role groups.
2. Fetches AKS credentials and exports every rendered-template value as an environment variable.
3. Installs Traefik and cert-manager via Helm, then applies the `letsencrypt-prod` `ClusterIssuer` (Azure DNS DNS-01).
4. Applies the storage class, the Key Vault `SecretProviderClass`, and the secret-sync Deployment that forces the CSI driver to materialize Key Vault secrets as Kubernetes Secrets.
5. Applies the audit-log forwarder and waits for it to be `Ready` — **Harbor's `core` container fails to start if the forwarder isn't reachable**, so ordering matters.
6. Renders and installs Harbor via Helm, pointed at the external PostgreSQL and Redis instances.
7. Applies the `harbor-tls` `Certificate` and the Traefik `IngressRoute`/`Middleware` resources for HTTPS, HTTP→HTTPS redirect, and HSTS.

### Terraform only

```bash
cd terraform
terraform init
terraform apply -var dns_zone_name=example.com -var dns_zone_resource_group=rg-dns-zones -var acme_email=you@example.com
```

## 🔎 Verification

**Harbor login:**
```bash
open "https://$(terraform -chdir=terraform output -raw harbor_fqdn)"
# admin / $(terraform -chdir=terraform output -raw harbor_admin_password)
```

**Audit logs in Log Analytics** (after logging in to Harbor at least once):
```kusto
ContainerLogV2
| where PodNamespace == "harbor" and ContainerName == "fluent-bit"
| extend Audit = parse_json(LogMessage)
| where isnotempty(Audit.log)
| project TimeGenerated, AuditEvent = tostring(Audit.log)
| order by TimeGenerated desc
```

**Metrics in Grafana:** open the endpoint from `terraform output -raw grafana_endpoint`, add an "Azure Monitor Managed Service for Prometheus" data source pointed at the Azure Monitor workspace, and run `harbor_up` in Explore.

**Private networking:** confirm PostgreSQL, Redis, and Key Vault all resolve to private IPs from inside the cluster:
```bash
kubectl run -it --rm dnsutils --image=ghcr.io/dnsutils/dnsutils --restart=Never -- \
  sh -c "nslookup $(terraform -chdir=terraform output -raw postgres_host)"
```

## 🧹 Cleanup

```bash
./cleanup.sh
```

This uninstalls the Helm releases, deletes the `harbor`/`traefik`/`cert-manager` namespaces, and runs `terraform destroy`. Review the confirmation prompt before running it against a shared cluster — PostgreSQL and Key Vault have `backup_retention_days`/`purge_protection_enabled` set, so full teardown may require extra manual steps (e.g. Key Vault purge) depending on your subscription's soft-delete policy.

## 🔐 Microsoft Entra ID OIDC SSO

Terraform provisions the Entra ID identity for Harbor SSO whenever `enable_oidc_auth = true` (the default), inside `modules/identity`:

- An app registration/SPN with a Terraform-generated client secret (1-year expiry), the `https://<harbor_fqdn>/c/oidc/callback` redirect URI, and delegated Graph scopes `openid`/`profile`/`email`/`offline_access`, pre-consented tenant-wide so users skip the consent prompt.
- Six Entra ID security groups, one per Harbor role, each assigned to the app's default role so they appear in the OIDC `groups` claim:

  | Harbor role | Variable | Default group name | Scope |
  |---|---|---|---|
  | System Admin | `harbor_admin_group_name` | `harbor-admins` | Global (`oidc_admin_group`) |
  | ProjectAdmin | `harbor_projectadmin_group_name` | `harbor-projectadmins` | Per-project |
  | Maintainer | `harbor_maintainer_group_name` | `harbor-maintainers` | Per-project |
  | Developer | `harbor_developer_group_name` | `harbor-developers` | Per-project |
  | Guest (read-only) | `harbor_guest_group_name` | `harbor-guests` | Per-project |
  | Limited Guest (pull-only) | `harbor_limited_guest_group_name` | `harbor-limited-guests` | Per-project |

- Initial members of `harbor-admins` come from `harbor_admin_group_member_upns` in `terraform.tfvars` — the other 5 groups start empty and are assigned per Harbor project after creation (Harbor UI → *Project* → *Members* → *+ User Group*, using the group object ID from `terraform output`).
- **Group matching is by object ID, not name** — Entra emits group object IDs in the `groups` claim, so Harbor's `oidc_admin_group` is set to the admin group's object ID.
- To use local Harbor authentication instead, set `enable_oidc_auth = false` before the first deployment.

## 🔒 Security notes

- Every stateful dependency (PostgreSQL, Redis, Key Vault) sits behind a private endpoint with public network access disabled; only the AKS subnet can reach them.
- Secrets never touch Terraform state as plaintext files: `harbor_admin_password`, `postgres_password`, `redis_password`, and the Harbor-internal secrets are generated with `random_password`, marked `sensitive` in outputs, and stored in Key Vault — Kubernetes only sees them via the Secrets Store CSI driver.
- cert-manager uses Azure Workload Identity (federated credential), not a client secret, scoped to `DNS Zone Contributor` on the single DNS zone.
- The Harbor OIDC client secret is a real secret (it lives in the `configureUserSettings` JSON blob, not a separate chart field); it's marked `sensitive` in Terraform outputs.
- `terraform.tfvars` is gitignored; only `terraform.tfvars.example` (placeholder values) is committed.
- **Caveat:** once `configureUserSettings` is set, all Harbor user-scope settings — including `auth_mode` — become read-only in the Harbor UI. Changing auth after this point means editing values and redeploying.

## 🛠️ Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `harbor-core` CrashLoopBackOff on first install | Audit-log forwarder not `Ready` yet | Check `kubectl rollout status deployment/harbor-audit-forwarder -n harbor`; re-run `helm upgrade` once it's ready |
| Certificate stuck in `Pending` | DNS-01 propagation delay, or Workload Identity misconfigured | `kubectl describe certificate harbor-tls -n harbor`; confirm the federated credential subject matches `system:serviceaccount:cert-manager:cert-manager` |
| `SecretProviderClass` doesn't create Kubernetes Secrets | `keyvault-secret-sync.yaml` pod not scheduled/running, or CSI driver identity lacks `Key Vault Secrets User` | `kubectl describe pod -n harbor -l app=harbor-secret-sync`; confirm the role assignment in `modules/keyvault` |
| Harbor can't reach PostgreSQL/Redis | Private DNS zone not linked to the AKS VNet, or NSG/firewall blocking the subnet | Verify `azurerm_private_dns_zone_virtual_network_link` in `modules/network`, and that AKS and Private Link subnets share the same VNet |
| Harbor still shows the local login form | `enable_oidc_auth = false`, or Terraform hasn't been re-applied after enabling it | Set `enable_oidc_auth = true`, re-run `terraform apply` then `./deploy.sh` |
| cert-manager gets 403 from Azure DNS | RBAC propagation delay (30–90s) | Re-check after a minute; confirm the zone-scoped `DNS Zone Contributor` role assignment exists |

## 📚 Further Reading

- [Harbor Helm chart](https://github.com/goharbor/harbor-helm)
- [cert-manager Azure DNS solver](https://cert-manager.io/docs/configuration/acme/dns01/azuredns/)
- [Traefik Helm chart](https://github.com/traefik/traefik-helm-chart)
- [Azure Key Vault Provider for Secrets Store CSI Driver](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver)
- [AKS-Harbor-Registry-Demo](../AKS-Harbor-Registry-Demo) — the simpler, bundled-database companion demo
