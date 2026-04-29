# Azure Private Link Service & Private Endpoint — Enterprise Hands-on Demo

A self-contained, production-shaped demo that lets you **see, touch, and break** the two pillars of Azure private connectivity:

1. **Azure Private Link Service (PLS)** — how a *provider* publishes its own internal service so other tenants can reach it privately.
2. **Azure Private Endpoint (PE)** — how a *consumer* attaches a NIC inside their own VNet that maps to either:
   - someone else's Private Link Service (scenario 1), or
   - a 1st-party Azure PaaS service like Storage / SQL / Key Vault (scenario 2).

By the end you will have answered the questions enterprises always ask:

> "Why do I need Private Link if I already have VNet peering?"
> "How does a SaaS provider in another tenant let me reach their service without ever exposing it to the public internet?"
> "Why does `mystorage.blob.core.windows.net` suddenly resolve to a `10.x.x.x` address?"
> "Who approves a Private Endpoint connection, and where is the audit trail?"

---

## 1. Concepts in 60 seconds

### Private Endpoint (the "consumer-side" object)
- A NIC injected into **your** subnet that gets a **private IP from your address space**.
- That IP is mapped (via the Microsoft backbone) to a specific resource — either a PaaS service (`groupId` = `blob`, `sqlServer`, `vault`, …) or a **Private Link Service** belonging to someone else.
- Traffic never traverses the public internet, even though the target may have a public FQDN.
- The matching **Private DNS Zone** (e.g. `privatelink.blob.core.windows.net`) is what makes the public hostname resolve to the new private IP.

### Private Link Service (the "provider-side" object)
- A way to publish **your own** Standard Internal Load Balancer behind an alias like `myservice.abcd1234-xxxx.region.azure.privatelinkservice`.
- Anyone you authorise can create a Private Endpoint pointing at that alias and reach your service privately.
- Has built-in **approval workflow**, **visibility scoping** (allow-list of subscriptions), and **NAT** so the provider never sees the consumer's IP space (no overlapping CIDR pain).
- Standard pattern for ISVs, shared-services teams, and central platform teams in large enterprises.

### What about DNS?
DNS behaves differently for the two PE flavours:

| Target | Microsoft-provided `privatelink.*` zone? | What you do |
|---|---|---|
| 1st-party PaaS (Storage, SQL, Key Vault, …) | ✅ Yes (e.g. `privatelink.blob.core.windows.net`) | Create the zone, link it to the consumer VNet, and add a `privateDnsZoneGroup` on the PE so the public FQDN resolves to the private IP. |
| Your own Private Link Service | ❌ No — Azure has no idea what hostname your service uses | **Bring your own Private DNS zone** (e.g. `provider.internal`), VNet-link it, and add an A record `app → <PE IP>`. |

This demo shows **both**: the Storage scenario uses `privatelink.blob.core.windows.net`; the PLS scenario uses a custom `provider.internal` zone with an `app` A record.

### Why not just peer the VNets?
| Concern | VNet peering | Private Link |
|---|---|---|
| Requires non-overlapping IP ranges | ✅ Yes | ❌ No (NAT'd) |
| Exposes both sides' entire address space | ✅ Yes | ❌ No — only one IP/port |
| Cross-tenant friendly | ⚠️ Hard | ✅ Designed for it |
| Per-consumer approval workflow | ❌ | ✅ |
| Granular per-service exposure | ❌ | ✅ |
| Cost model | Per GB of peered traffic | Per-hour PE + per-GB |

Use peering for **hub-and-spoke within one org**. Use Private Link when you need **service-level, multi-tenant, audited** exposure.

---

## 2. What this demo deploys

Two **completely isolated** VNets in a single resource group (so the lab is cheap and easy), with **no peering** between them — proving traffic flows over Private Link only.

```
┌────────────────── Provider VNet (10.10.0.0/16) ──────────────────┐
│                                                                   │
│  snet-backend (10.10.1.0/24)        snet-pls (10.10.2.0/24)       │
│  ┌────────────┐  ┌────────────┐                                   │
│  │ be-vm-0    │  │ be-vm-1    │   ┌───────────────────────────┐   │
│  │  nginx :80 │  │  nginx :80 │   │ Private Link Service      │   │
│  └─────┬──────┘  └─────┬──────┘   │ (NAT IPs from snet-pls)   │   │
│        └──────┬────────┘          │ alias: ...privatelink...  │   │
│               ▼                   └────────────┬──────────────┘   │
│       ┌──────────────────┐                     │                  │
│       │ Internal Std LB  │◄────────────────────┘                  │
│       │ FE 10.10.1.10:80 │                                        │
│       └──────────────────┘                                        │
└───────────────────────────────────────────────────────────────────┘
                                 │  (Microsoft backbone — no peering)
                                 ▼
┌────────────────── Consumer VNet (10.20.0.0/16) ──────────────────┐
│                                                                   │
│  snet-jumpbox (10.20.1.0/24)        snet-pe (10.20.2.0/24)        │
│  ┌────────────┐                    ┌───────────────────────────┐  │
│  │ jumpbox VM │ ─── curl ────────► │ Private Endpoint NIC      │  │
│  │ +Public IP │                    │   IP: 10.20.2.x           │  │
│  └────────────┘                    └───────────────────────────┘  │
│                                    ┌───────────────────────────┐  │
│                                    │ PE → Storage (blob)       │  │
│                                    │   Private DNS zone linked │  │
│                                    └───────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

| Layer | Resource | Role |
|---|---|---|
| Provider | 2× Linux VMs running nginx (cloud-init) | Backend pool — each prints its hostname so you can watch the LB rotate |
| Provider | Standard Internal Load Balancer | Frontend exposed inside provider VNet only |
| Provider | **Azure Private Link Service** | Wraps the ILB and hands out an alias |
| Consumer | Jumpbox VM (public IP, SSH only) | Your test client |
| Consumer | **Private Endpoint → PLS** | Maps a 10.20.2.x IP to the provider service |
| Consumer | **Custom Private DNS zone** `provider.internal` + A record `app` | Friendly FQDN → PE private IP |
| Consumer | **Private Endpoint → Storage Blob** | Demonstrates PaaS pattern + `privatelink.blob.*` DNS Zone |

---

## 3. Prerequisites

- Azure subscription with permission to create networking and compute resources.
- Azure CLI ≥ 2.60, signed in (`az login`) and the right subscription set (`az account set --subscription <id>`).
- `openssl` and `curl` (used by `deploy.sh` to generate a password and detect your public IP).
- About **€2–€5/day** if you leave it running (2× B2s VMs + 1× B2s jumpbox + 1× ILB + 1× PLS + 2× PE).

> **Auth model.** For lab simplicity these VMs use **password authentication**. `deploy.sh` auto-generates an Azure-compliant password (20 chars, mixed case + digits + special) and stores it in `./.vm-password` (chmod 600, gitignored). The jumpbox NSG is locked down to your detected public IP automatically.

## 4. Deploy

```bash
cd Azure-Private-Link-Demo
chmod +x deploy.sh cleanup.sh

# Optional overrides
export RESOURCE_GROUP_NAME=rg-private-link-demo
export LOCATION=northeurope
# export ADMIN_PASSWORD='YourOwnSecret!23'   # otherwise auto-generated
# export ALLOWED_SSH_SOURCE_IP=203.0.113.10/32 # otherwise auto-detected

./deploy.sh
```

The script will:
1. Create the resource group.
2. Generate (or reuse) an Azure-compliant VM password and save it to `./.vm-password`.
3. Detect your public IP via `api.ipify.org` and lock the jumpbox NSG to `<ip>/32`.
4. Run `az deployment group create` against [main.bicep](main.bicep).
5. Print the jumpbox public IP, the VM credentials, the PE private IP, and copy-pasteable next steps.

---

## 5. Walk-through — the exercises that matter

> SSH to the jumpbox first: `ssh azureuser@<jumpboxPublicIp>` and paste the password printed by `deploy.sh` (also stored in `./.vm-password`). All commands below are run **from the jumpbox** unless stated otherwise.

### Exercise A — Reach a service in another VNet without peering

```bash
# Replace with the values printed by deploy.sh.
PE_IP=10.20.2.4
FQDN=app.provider.internal

# 1) By IP — raw Private Endpoint reachability
curl http://$PE_IP
# → "Hello from plkdemo-be-0 — provider backend"

# 2) By friendly hostname — the custom Private DNS zone in action
dig +short $FQDN          # → 10.20.2.x  (the PE NIC IP)
curl http://$FQDN

# 3) Watch the Standard LB rotate between backend VMs
for i in {1..10}; do curl -s http://$FQDN; done
```
**What just happened?** The `app.provider.internal` lookup hit the **Private DNS zone** linked to the consumer VNet, returning the PE NIC IP `10.20.2.x`. The packet then traversed the Microsoft backbone via the Private Link Service, was NAT'd onto the provider's `snet-pls`, hit the ILB frontend `10.10.1.10`, and was distributed across two backend VMs you never had a route to. No peering. No public IP. No firewall hole.

This is **option 2** (BYO DNS zone) — the production pattern. PLS-backed PEs do not get a Microsoft-published `privatelink.*` zone, so you own the namespace.

### Exercise B — Prove there is no VNet peering

From your **laptop** (not the jumpbox):
```bash
az network vnet peering list -g rg-private-link-demo --vnet-name plkdemo-provider-vnet -o table
az network vnet peering list -g rg-private-link-demo --vnet-name plkdemo-consumer-vnet -o table
# Both return empty. Connectivity is 100% via Private Link.
```

### Exercise C — Watch the approval workflow

The PLS in this lab auto-approves connections from the deploying subscription. Toggle that to manual and feel the gate:
```bash
PLS_ID=$(az network private-link-service show -g rg-private-link-demo -n plkdemo-pls --query id -o tsv)

# List all PE connections to the PLS (shows status = Approved)
az network private-endpoint-connection list --id $PLS_ID -o table
```
In a real enterprise you'd remove `autoApproval` in [modules/provider.bicep](modules/provider.bicep) so the provider team manually approves each consumer — a built-in governance checkpoint with full activity-log audit trail.

### Exercise D — Private Endpoint to a PaaS service (Azure Storage)

The Bicep also created a Storage Account with `publicNetworkAccess: Disabled` and a Private Endpoint + Private DNS Zone (`privatelink.blob.core.windows.net`) linked to the consumer VNet. From the jumpbox:

```bash
ST=<storageAccountName from output>

# DNS resolution: the public FQDN now returns a PRIVATE IP
dig +short ${ST}.blob.core.windows.net
# 10.20.2.x   ← Private Endpoint NIC

# Resolution from outside Azure (run on your laptop) returns the public IP — but:
# the storage account refuses public traffic, so it is unreachable that way.
```

```bash
# From the jumpbox — install the CLI and prove access works privately
sudo snap install azcopy
# Or use the Azure CLI on the jumpbox after `az login --identity` if you assign a
# managed identity to the VM and grant 'Storage Blob Data Reader'.
```

### Exercise E — Break it on purpose (great for understanding)

1. **Delete the Private DNS zone link** and re-run `dig`. The FQDN now resolves to the PUBLIC IP, but traffic still fails because the Storage Account blocks public access. This is the classic "DNS gap" that breaks Private Endpoint deployments in production — always automate DNS zone linking via Azure Policy.
2. **Set the PLS visibility to a different subscription ID.** Recreate the PE — it will land in `Pending` state forever until approved.
3. **Disable `privateLinkServiceNetworkPolicies` on `snet-pls`** (it's already disabled here). Try toggling it on in the portal and re-deploying — the PLS deployment fails. That subnet flag is a frequent gotcha.

---

## 6. File map

| File | Purpose |
|---|---|
| [main.bicep](main.bicep) | Top-level orchestration of the three modules |
| [main.bicepparam](main.bicepparam) | Parameter values (reads `SSH_PUBLIC_KEY` env var) |
| [modules/provider.bicep](modules/provider.bicep) | Provider VNet, ILB, 2 nginx VMs, **Private Link Service** |
| [modules/consumer.bicep](modules/consumer.bicep) | Consumer VNet, jumpbox, **Private Endpoint → PLS**, custom Private DNS zone (`provider.internal`) |
| [modules/storage-pe.bicep](modules/storage-pe.bicep) | Storage account, **Private Endpoint → blob** + `privatelink.blob.*` Private DNS Zone |
| [deploy.sh](deploy.sh) | One-shot deployment + post-deploy guidance |
| [cleanup.sh](cleanup.sh) | Deletes the entire resource group with confirmation |

---

## 7. Enterprise design notes (the bits production teams forget)

- **DNS is 80% of Private Link incidents.** Never rely on humans to create the right `privatelink.*` zone. Use **Azure Policy** built-ins like `Configure private DNS zone group` for each PaaS service so PEs auto-register.
- **Centralise DNS in the hub** if you operate hub-and-spoke. Link the `privatelink.*` zones once to the hub VNet and forward from spokes via custom DNS, or use **Azure Private DNS Resolver**.
- **Subnet sizing.** Each PE consumes one IP. Keep PE subnets large (≥ /27) and dedicated. PLS NAT IPs can grow up to 8 per service — size `snet-pls` accordingly.
- **Charge-back.** PE is billed per hour and per GB of inbound + outbound — surface it in your FinOps tagging strategy.
- **Cross-region.** A Private Endpoint and the resource it targets can live in **different regions**, but DNS and latency planning matter. PLS-to-PE works cross-region/cross-tenant transparently.
- **Approval governance.** Treat the PLS connection list like an external API gateway: log every approve/reject in the activity log and route to your SIEM.
- **NSG on PE subnets.** Until [the GA of NSG support for Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview), `privateEndpointNetworkPolicies = Disabled` was required. It's now optional but keep it disabled unless you're consciously applying NSGs.

---

## 8. Tear down

```bash
./cleanup.sh
# Type the resource group name to confirm.
```

This deletes the whole resource group asynchronously (no leftover Private DNS zones — they're inside the same RG).

---

## 9. Further reading

- [What is Azure Private Link?](https://learn.microsoft.com/azure/private-link/private-link-overview)
- [Private Endpoint DNS configuration](https://learn.microsoft.com/azure/private-link/private-endpoint-dns)
- [Approve, reject, or remove a Private Endpoint connection](https://learn.microsoft.com/azure/private-link/manage-private-endpoint)
- [Private Link Service overview](https://learn.microsoft.com/azure/private-link/private-link-service-overview)
