# AKS Harbor Production Demo

This demo implements the production Harbor architecture captured in the saved plan at [../plan/aks-harbor-production-demo.md](../plan/aks-harbor-production-demo.md).

It is intentionally shaped as a production-grade Harbor deployment on AKS, with:

- Azure Kubernetes Service with workload identity and CSI secret sync
- Private networking for PostgreSQL, Redis, and Key Vault
- Azure Files Premium ZRS NFS for shared registry storage
- External PostgreSQL Flexible Server and Azure Cache for Redis Premium
- cert-manager + Traefik for TLS ingress
- Harbor OIDC login via Microsoft Entra ID
- Azure Monitor + Grafana integration
- Terraform + Helm deployment automation

## Structure

```text
AKS-Harbor-Production-Demo/
├── .gitignore
├── README.md
├── deploy.sh
├── cleanup.sh
├── terraform/
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── network/
│       ├── aks/
│       ├── postgres/
│       ├── redis/
│       ├── keyvault/
│       ├── identity/
│       └── alerts/
├── kubernetes-manifests/
│   ├── namespace.yaml
│   ├── cluster-issuer.yaml.tpl
│   ├── harbor-certificate.yaml.tpl
│   ├── harbor-ingress-route.yaml.tpl
│   ├── harbor-values.yaml.tpl
│   ├── storageclass-azurefile-zrs-nfs.yaml
│   ├── secretproviderclass.yaml.tpl
│   └── keyvault-secret-sync.yaml
├── azure-config/
│   └── monitoring/
└── scripts/
    └── dr-drill.sh
```

## Prerequisites

- Azure CLI logged in
- Terraform >= 1.6.0
- kubectl
- helm
- An existing Azure DNS zone already delegated to Azure DNS
- Permission to create resource groups, AKS, PostgreSQL, Redis, Key Vault, and application registrations
- Entra permissions to create security groups and grant delegated permission consent

## Quick start

```bash
cd AKS-Harbor-Production-Demo/terraform
cp terraform.tfvars.example terraform.tfvars
# Update values for your environment
cd ..
./deploy.sh
```

## Microsoft Entra ID SSO

SSO is enabled by default with `enable_oidc_auth = true`. Terraform creates the Harbor web application, service principal, one-year client secret, callback URI, group claim configuration, and these security groups:

| Entra group | Harbor role | Scope |
| --- | --- | --- |
| `harbor-admins` | System Administrator | Global Harbor access |
| `harbor-projectadmins` | Project Administrator | Assign per project |
| `harbor-maintainers` | Maintainer | Assign per project |
| `harbor-developers` | Developer | Assign per project |
| `harbor-guests` | Guest | Assign per project |
| `harbor-limited-guests` | Limited Guest | Assign per project |

Add the first administrator before deployment in `terraform.tfvars`:

```hcl
harbor_admin_group_member_upns = ["admin@contoso.com"]
```

The OIDC redirect URI is generated from `harbor_fqdn` as `https://<harbor-fqdn>/c/oidc/callback`. The Entra `groups` claim contains group object IDs, so Harbor's `oidc_admin_group` is configured with the object ID of `harbor-admins`, not its display name. After creating a Harbor project, assign the other groups from Harbor UI under **Project > Members > Add User Group**, using the group object ID from Terraform output.

The client secret is read from a sensitive Terraform output by `deploy.sh` and rendered only into the ignored `.rendered/harbor-values.yaml`. Terraform state still contains the secret and must be protected with an appropriate remote backend for shared or production use. To use local Harbor authentication instead, set `enable_oidc_auth = false` before the first deployment.

## Notes

This is the production-oriented companion to the simpler Harbor demo in [../AKS-Harbor-Registry-Demo](../AKS-Harbor-Registry-Demo). It intentionally uses managed, external data services and private networking so it resembles a production deployment more closely than the basic tutorial version.
