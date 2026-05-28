# AKS Argo CD Extension with Microsoft Entra SSO

Deploy [Argo CD](https://argo-cd.readthedocs.io/) on Azure Kubernetes Service via the **`Microsoft.ArgoCD` cluster extension**, with end-to-end Terraform automation for:

- AKS cluster with **Workload Identity** + **OIDC issuer** enabled
- **Azure NGINX (Application Routing) add-on** for ingress
- **Azure Key Vault** holding the TLS certificate used by the Argo CD ingress
- **Microsoft Entra ID** application + group-based RBAC for **Argo CD SSO**
- The **Argo CD extension** installed onto the cluster and pre-wired with the
  Entra ID OIDC settings

References:

- AKS / Arc tutorial: <https://learn.microsoft.com/azure/azure-arc/kubernetes/tutorial-use-gitops-argocd>
- AKS blog – Argo CD extension with Microsoft Entra: <https://blog.aks.azure.com/2026/04/22/argocd-extension-with-microsoft-entra>

## 📁 Layout

```
AKS-ArgoCD-Extension/
├── README.md
├── commands.sh                       # Post-apply helper (kubeconfig, ingress, DNS, sample app)
├── terraform/
│   ├── providers.tf                  # azurerm / azuread / azapi / random
│   ├── variables.tf                  # All tunables (DNS zone, cert, admin group...)
│   ├── main.tf                       # RG, Log Analytics, AKS (+App Routing), Key Vault, cert
│   ├── entra.tf                      # Entra ID app, SP, client secret for Argo CD SSO
│   ├── argocd.tf                     # Microsoft.ArgoCD extension (azapi)
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── k8s/
    ├── argocd-ingress.yaml           # Argo CD ingress (App Routing + KV cert)
    ├── argocd-rbac-cm.yaml           # Entra group → admin role mapping
    └── sample-application.yaml       # Demo Argo CD Application (guestbook)
```

## 🧱 What gets created

| Resource | Notes |
|---|---|
| `rg-argocd-demo` (resource group) | Container for all demo resources |
| `aks-argocd-demo` (AKS cluster) | Workload Identity + OIDC, Cilium overlay, App Routing add-on, node RG `rg-argocd-demo-nodes` |
| `log-argocd-demo` (Log Analytics) | Container Insights destination |
| `kv-argocd-demo-<rand>` (Key Vault) | RBAC-authorized; holds the ingress PFX |
| `argocd-ingress-tls` (Key Vault cert) | Imported from a local `.pfx` file |
| Entra ID application + SP + client secret | OIDC IdP for Argo CD via Dex |
| `Microsoft.ArgoCD` cluster extension | Installs Argo CD into the `argocd` namespace |

The custom **node resource group** `rg-<project>-<env>-nodes` follows the
repository's AKS naming convention.

## ✅ Prerequisites

- Terraform `>= 1.6`
- Azure CLI logged in (`az login`) to a subscription where you can:
  - create resource groups, AKS clusters, Key Vaults, role assignments
  - register Entra ID applications and grant client secrets
- An **existing public Azure DNS zone** that you control (e.g. `example.com`)
- A **PFX certificate** that covers the Argo CD hostname (e.g. wildcard for
  `*.example.com` or a SAN cert for `argocd.example.com`)
- The Microsoft Entra ID **security group** whose members should be Argo CD
  admins (you'll provide its object ID)

> The `Microsoft.ArgoCD` extension is currently in **preview**. Make sure the
> `k8s-extension` CLI extension is installed (`az extension add --name k8s-extension`)
> and that the `Microsoft.KubernetesConfiguration` resource provider is
> registered on the subscription.

## 🚀 Deploy

```bash
cd AKS-ArgoCD-Extension/terraform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set:
#   dns_zone_name / dns_zone_resource_group
#   argocd_hostname (e.g. argocd.example.com)
#   certificate_pfx_path / certificate_pfx_password
#   argocd_admin_group_object_id

terraform init
terraform apply
```

Once `apply` finishes, run the post-deploy helper from the demo root:

```bash
cd ..
./commands.sh
```

`commands.sh` will:

1. Fetch kubeconfig for the cluster.
2. Wait for the `Microsoft.ArgoCD` extension to finish provisioning.
3. Render `k8s/argocd-ingress.yaml` with the real Key Vault certificate URI and
   hostname and apply it (the App Routing controller mounts the cert via
   Secrets Store CSI).
4. Print the public IP of the App Routing NGINX service so you can create the
   matching DNS A record.
5. Apply the sample Argo CD `Application`.
6. Print the initial admin password (use it once, then sign in with SSO).

## 🔐 SSO sign-in

After DNS resolves, open `https://<argocd_hostname>/` and choose **Log in via
Microsoft Entra ID**. Members of the configured admin group get the built-in
Argo CD `admin` role via the policy:

```
g, <argocd_admin_group_object_id>, role:admin
```

Everyone else falls back to `role:readonly` (`policy.default`).

The Entra ID application is created with:

- redirect URIs `https://<argocd_hostname>/auth/callback` and
  `https://<argocd_hostname>/api/dex/callback`
- `groups` optional claim emitted in ID and access tokens
- delegated `User.Read` and `GroupMember.Read.All` Microsoft Graph permissions

You may still need an Entra ID admin to **grant tenant-wide admin consent** for
the delegated Graph permissions on first use.

## 🧹 Clean up

```bash
cd terraform
terraform destroy
```

`terraform destroy` removes the extension, AKS cluster, Key Vault, and Entra ID
application. The DNS zone and any DNS A records you added manually outside
Terraform are left untouched.

## 📝 Notes & caveats

- The configuration setting keys used for the `Microsoft.ArgoCD` extension
  (`sso.provider`, `sso.entra.clientId`, …) reflect the public preview schema at
  the time of writing. If your extension version exposes different keys,
  update `terraform/argocd.tf` accordingly.
- The Entra ID client secret is stored in Terraform state. Use a remote backend
  with state encryption (e.g. Azure Storage with CMK) for any non-throwaway
  environment.
- The App Routing add-on automatically gets `DNS Zone Contributor` on the zone
  passed via `dns_zone_ids` so it can manage the public DNS A record for
  ingresses with the matching host. The `commands.sh` step that creates the
  record manually is a safety net for clusters where automatic DNS record
  creation is disabled.
