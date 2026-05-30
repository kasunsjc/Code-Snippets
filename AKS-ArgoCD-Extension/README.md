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
├── commands.sh                             # Post-apply helper (kubeconfig, ingress, DNS, sample app)
├── terraform/
│   ├── providers.tf                        # azurerm / azuread / azapi / random
│   ├── variables.tf                        # All tunables (DNS zone, cert, admin group...)
│   ├── main.tf                             # Root – RG, Log Analytics, module calls
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── aks/                            # AKS cluster with App Routing + Cilium
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── keyvault/                       # Key Vault, cert import, App Routing KV attach
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── entra/                          # Entra ID app, SP, client secret for SSO
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── argocd-extension/               # Microsoft.ArgoCD extension (azapi)
│           ├── main.tf
│           ├── variables.tf
│           ├── versions.tf
│           └── outputs.tf
└── k8s/
    ├── argocd-ingress.yaml                 # Argo CD ingress (App Routing + KV cert)
    ├── argocd-rbac-cm.yaml                 # Entra group → admin role mapping
    └── sample-application.yaml             # Demo Argo CD Application (guestbook)
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

### Required tools

| Tool | Min version | Install |
|---|---|---|
| Terraform | `>= 1.6` | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| Azure CLI | latest | `brew install azure-cli` |
| kubectl | latest | `az aks install-cli` |
| `k8s-extension` CLI extension | latest | `az extension add --name k8s-extension` |
| `aks-preview` CLI extension | latest | `az extension add --name aks-preview` |

### Azure permissions

The identity running `terraform apply` needs:

- **Contributor** (or equivalent) on the target subscription to create AKS, Key Vault, Log Analytics and managed identities
- **Role Based Access Control Administrator** (or User Access Administrator) to create role assignments for the App Routing identity and the Terraform deployer principal
- **Application Administrator** (or Cloud Application Administrator) in Entra ID to register the SSO application

### Required resources (pre-existing)

- An **existing public Azure DNS zone** you control (e.g. `example.com`) in any resource group
- A **PFX certificate** covering the Argo CD hostname — either a wildcard (`*.example.com`) or a single-SAN cert. This is imported into Key Vault by Terraform.
  - The certificate must come from a **publicly trusted CA** (DigiCert, Let's Encrypt, etc.). Self-signed certs will show `ERR_CERT_AUTHORITY_INVALID` in browsers.

### Azure resource provider registrations

Ensure these are registered on the subscription before running `terraform apply`:

```bash
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ContainerService
```

Check status with:

```bash
az provider show -n Microsoft.KubernetesConfiguration --query registrationState -o tsv
```

> The `Microsoft.ArgoCD` extension is currently in **preview**. The
> `k8s-extension` CLI extension is required for `az k8s-extension` commands
> used in `deploy.sh`.

## 🚀 Deploy

A single script handles both Terraform provisioning and post-deploy K8s
configuration:

```bash
cd AKS-ArgoCD-Extension

# Create terraform.tfvars with required variables:
cat > terraform/terraform.tfvars <<'EOF'
dns_zone_name           = "example.com"
dns_zone_resource_group = "dns-zones-rg"
argocd_hostname         = "argocd.example.com"
certificate_pfx_path    = "./star_example_com.pfx"
EOF

# Deploy everything in one step:
./deploy.sh
```

`deploy.sh` will:

1. Run `terraform init` and `terraform apply` to provision all Azure infrastructure (AKS, Key Vault, Entra ID app + group, Argo CD extension).
2. Fetch kubeconfig for the cluster.
3. Wait for the `Microsoft.ArgoCD` extension to finish provisioning.
4. Restart `external-dns` so it picks up fresh RBAC token after role assignments propagate.
5. Wait for the `NginxIngressController` CR to become available, then patch it with the Key Vault certificate URI. This mirrors what the Azure Portal does when you configure HTTPS on the App Routing add-on.
6. Wait for the App Routing operator to sync the cert from Key Vault into the cluster.
7. Apply `k8s/argocd-ingress.yaml` with the real hostname.
8. Print the public IP of the App Routing NGINX service so you can verify the DNS A record.
9. Apply the sample Argo CD `Application`.
10. Print the initial admin password.

To destroy all resources:

```bash
./deploy.sh --destroy
```

## 🔐 SSO sign-in

After DNS resolves, open `https://<argocd_hostname>/` and choose **Log in via
Microsoft Entra ID**. Members of the **argocd-admins** group (created
automatically by Terraform and populated with the deploying user) get the
built-in Argo CD `admin` role via the policy:

```
g, <argocd_admin_group_object_id>, role:admin
```

You can manage group membership in the Azure portal or with `az ad group member add`.

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
  update `terraform/modules/argocd-extension/main.tf` accordingly.
- The Entra ID client secret is stored in Terraform state. Use a remote backend
  with state encryption (e.g. Azure Storage with CMK) for any non-throwaway
  environment.
- The App Routing add-on automatically gets `DNS Zone Contributor` on the zone
  passed via `dns_zone_ids` so it can manage the public DNS A record for
  ingresses with the matching host. The `commands.sh` step that creates the
  record manually is a safety net for clusters where automatic DNS record
  creation is disabled.

---

## ⚠️ Known issues & deployment tips

These are real issues encountered during development. Read before deploying.

### 1. TLS shows `ERR_CERT_AUTHORITY_INVALID` — nginx using self-signed cert

**Root cause:** The App Routing nginx controller ships with a self-signed fallback
certificate. It only switches to your real cert after the `NginxIngressController`
CR is patched with `spec.defaultSSLCertificate.keyVaultURI`.

**How it works (and how the Portal does it):**  
The Azure Portal's _App Routing → HTTPS → select Key Vault_ flow patches this same
CR. `deploy.sh` reproduces that exact step:

```bash
kubectl patch nginxingresscontroller default --type=merge \
  -p '{"spec":{"defaultSSLCertificate":{"keyVaultURI":"<kv-cert-uri>"}}}'
```

The App Routing operator then creates a `SecretProviderClass`, the Secrets Store CSI
driver syncs the cert from Key Vault into a `kubernetes.io/tls` Secret in
`app-routing-system`, and nginx restarts with
`--default-ssl-certificate=app-routing-system/keyvault-nginx-default`.

**Do not** add `kubernetes.azure.com/tls-cert-keyvault-uri` as a per-ingress
annotation — that is a different, per-ingress mechanism and is not needed when
the default cert is set at the controller level.

---

### 2. `kubectl patch nginxingresscontroller` fails on a fresh cluster

**Root cause:** The `NginxIngressController default` CR is created asynchronously
by the App Routing addon after the cluster becomes ready. Running the patch
immediately after `az aks get-credentials` can hit a `not found` error.

**Fix:** `deploy.sh` waits with:

```bash
kubectl wait nginxingresscontroller default --for=condition=Available --timeout=5m
```

---

### 3. Secrets Store CSI Driver must be explicitly enabled in Terraform

**Root cause:** `az aks approuting update --attach-kv` implicitly enables the
Secrets Store CSI driver. Terraform's `azurerm_kubernetes_cluster` does **not**
enable it by default — the App Routing operator silently fails to mount the KV
cert without it.

**Fix:** The `key_vault_secrets_provider` block in `modules/aks/main.tf` enables it:

```hcl
key_vault_secrets_provider {
  secret_rotation_enabled  = true
  secret_rotation_interval = "2m"
}
```

---

### 4. App Routing identity needs `Key Vault Certificate User`, not `Key Vault Secrets User`

**Root cause:** The `az aks approuting update --attach-kv` command grants
`Key Vault Certificate User` (not `Key Vault Secrets User`) to the App Routing
managed identity. `Key Vault Certificate User` permits reading the backing secret
of a certificate (`getSecret` action) which is how the CSI driver retrieves the
private key. `Key Vault Secrets User` alone is insufficient.

**Where it's configured:** `modules/keyvault/main.tf`:

```hcl
resource "azurerm_role_assignment" "approuting_kv_cert_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = var.app_routing_object_id
}
```

---

### 5. `external-dns` gets 403 on DNS zones — needs Reader on the resource group

**Root cause:** `external-dns` lists all DNS zones at the **resource group** level
before accessing a specific zone. `DNS Zone Contributor` scoped to the zone alone
does not grant `Microsoft.Network/dnsZones/read` at the RG level, causing a 403.

**Fix:** Two role assignments in `main.tf`:

```hcl
# DNS operations on the specific zone
resource "azurerm_role_assignment" "approuting_dns_zone_contributor" {
  role_definition_name = "DNS Zone Contributor"
  scope                = data.azurerm_dns_zone.this.id
  ...
}

# Zone list enumeration at RG level (needed by external-dns)
resource "azurerm_role_assignment" "approuting_dns_rg_reader" {
  role_definition_name = "Reader"
  scope                = data.azurerm_resource_group.dns_zones.id
  ...
}
```

---

### 6. RBAC role assignments take time to propagate

**Root cause:** Azure RBAC assignments can take 30–90 s to propagate. `external-dns`
starts immediately after the cluster is ready and can crash with 403 if it queries
the DNS zone before the role assignments are active.

**Fix:** A `time_sleep` resource in `main.tf` waits 90 s after all DNS role
assignments are created before Terraform signals completion. `deploy.sh` also
restarts `external-dns` after kubeconfig is fetched to force a fresh token:

```bash
kubectl -n app-routing-system rollout restart deployment external-dns
```

---

### 7. Entra ID Graph permissions require tenant-wide admin consent

**Root cause:** The SSO application requests delegated `GroupMember.Read.All`
(to resolve group membership for the Argo CD admin policy). This permission
requires an Entra ID admin to grant tenant-wide consent — Terraform creates the
permission grant in the app registration but cannot consent on behalf of the tenant.

**Fix:** After `terraform apply`, an Entra ID Global Administrator or Privileged
Role Administrator must grant consent:

```bash
# Via Azure Portal:
# Entra ID → App registrations → <app> → API permissions → Grant admin consent

# Or via Azure CLI:
az ad app permission admin-consent --id <application_object_id>
```
