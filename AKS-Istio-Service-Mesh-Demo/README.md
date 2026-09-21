# AKS Istio Service Mesh Add-on Deep Dive

A hands-on deep dive into the **Istio-based service mesh add-on for Azure Kubernetes Service (AKS)**: what it actually installs, mutual TLS, traffic management (canary/weighted routing, header-based routing, fault injection), zero-trust authorization policies, ingress, observability, and — critically — where the managed add-on's guardrails stop and when you should reach for a self-managed, open-source Istio install instead.

> **Not to be confused with:** the [`AKS-Istio-Gateway-API`](../AKS-Istio-Gateway-API/README.md) demo in this repo, which covers the **App Routing (Istio) add-on** — a lightweight, ingress-only Envoy gateway with no sidecars, no mesh, and no CRDs. This demo covers the full **Istio service mesh add-on**: sidecar injection, `istiod`, mTLS everywhere, and the complete Istio CRD surface. See [When to choose which](#when-to-choose-which) for a side-by-side comparison of all three options (App Routing Istio, the mesh add-on, and self-managed OSS Istio).

> **References:**
> [Istio-based service mesh add-on for AKS](https://learn.microsoft.com/azure/aks/istio-about) ·
> [Deploy the add-on](https://learn.microsoft.com/azure/aks/istio-deploy-addon) ·
> [Upgrade the add-on](https://learn.microsoft.com/azure/aks/istio-upgrade) ·
> [Performance & scaling](https://learn.microsoft.com/azure/aks/istio-scale) ·
> [`azurerm_kubernetes_cluster` `service_mesh_profile`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster)

---

## What this demo builds

```mermaid
graph TB
    subgraph Azure["Azure Resource Group"]
        subgraph AKS["AKS Cluster (service_mesh_profile.mode = Istio)"]
            subgraph MeshSys["aks-istio-system namespace"]
                Istiod["istiod (control plane)<br/>revision: asm-X-Y"]
            end
            subgraph MeshIngress["aks-istio-ingress namespace"]
                GW["aks-istio-ingressgateway-external<br/>(Envoy, HPA-managed)"]
            end
            subgraph Default["default namespace (istio.io/rev=asm-X-Y label)"]
                PP["productpage + sidecar"]
                RV1["reviews-v1 + sidecar"]
                RV2["reviews-v2 + sidecar"]
                RV3["reviews-v3 + sidecar"]
                RT["ratings + sidecar"]
                DT["details + sidecar"]
            end
        end
        LB["Azure Load Balancer<br/>(public IP)"]
        LAW["Log Analytics Workspace"]
        PROM["Azure Monitor workspace<br/>(managed Prometheus)"]
        GRAF["Azure Managed Grafana"]
    end

    Internet(("Client")) --> LB --> GW
    GW -->|"Gateway + VirtualService"| PP
    PP --> RV1 & RV2 & RV3
    RV1 & RV2 & RV3 --> RT
    PP --> DT
    Istiod -.->|"mTLS certs + xDS config"| PP & RV1 & RV2 & RV3 & RT & DT & GW
    AKS -->|oms_agent| LAW
    AKS -->|monitor_metrics| PROM --> GRAF
```

| Layer | What's provisioned | How |
|---|---|---|
| Resource group + AKS cluster | Azure CNI Overlay, standard LB, system node pool | Terraform (`terraform/main.tf`) |
| **Istio add-on** | `istiod` control plane + external ingress gateway, via `service_mesh_profile { mode = "Istio" }` | Terraform |
| Observability (officially verified path) | Log Analytics, Azure Monitor managed Prometheus, Azure Managed Grafana | Terraform |
| Sample mesh app | Istio's `bookinfo` app (productpage/details/reviews v1-v3/ratings) | `deploy.sh` (`kubectl apply` from the istio/istio release matching the installed revision) |
| Traffic management | `DestinationRule` subsets, weighted/canary `VirtualService`, header-based routing, fault injection | `kubernetes-manifests/traffic-management/` |
| Security | Mesh-wide strict mTLS (`PeerAuthentication`), identity-based `AuthorizationPolicy` | `kubernetes-manifests/security/` |
| Ingress | Istio `Gateway` + `VirtualService` bound to the AKS-managed external ingress gateway | `kubernetes-manifests/ingress/` |

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Azure subscription** with quota for the chosen node VM size (`Standard_D4ds_v5` x 3 by default) | |
| **Azure CLI >= 2.57.0** | Required by the add-on's `az aks mesh` command group. Run `az --version`. |
| **`aks-preview` CLI extension** | Only needed for optional day-2 diagnostics (`az aks mesh get-revisions`, `az aks mesh get-upgrades`). `deploy.sh` installs/updates it best-effort; not required for the Terraform-driven deploy in this demo. |
| **Terraform >= 1.6** | Provisions the AKS cluster with the add-on enabled. |
| **kubectl** | Any recent version compatible with your target Kubernetes version. |
| **jq** | Used by `deploy.sh` to parse the `istio_revisions` Terraform output. |
| **`istioctl` (optional)** | Only needed for advanced day-2 operations such as revision-tag based canary upgrades ([Upgrade the add-on](https://learn.microsoft.com/azure/aks/istio-upgrade)) — not required for this demo. |
| **AKS cluster version >= 1.23** | Enforced by Terraform/AKS itself; `terraform.tfvars.example` defaults to a recent GA minor version. |
| No **Open Service Mesh (OSM) add-on** and no **self-managed Istio install** already on the target cluster | The Istio add-on refuses to coexist with either — see [Limitations](#limitations-of-the-aks-istio-add-on). |

---

## Deploying

```bash
cd AKS-Istio-Service-Mesh-Demo
az login
./deploy.sh
```

`deploy.sh` runs `terraform apply` (creating the resource group, AKS cluster with the Istio add-on, and the observability stack), fetches credentials, waits for `istiod`, labels the `default` namespace for sidecar injection, deploys the `bookinfo` sample app, and applies the baseline traffic-management/security/ingress manifests. It prints the ingress gateway's public IP and the Azure Managed Grafana endpoint at the end.

To customize the deployment (region, node size, ingress gateway placement, a pinned Istio revision, etc.), copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and edit before running `deploy.sh`.

---

## Demo walkthrough

### 1. Verify the control plane and data plane

```bash
kubectl get pods -n aks-istio-system                 # istiod
kubectl get pods -n aks-istio-ingress                 # external ingress gateway
kubectl get pods -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
# every bookinfo pod should show 2 containers: the app + istio-proxy
```

### 2. Traffic management — canary rollout, header routing, fault injection

The baseline (`virtualservice-all-v1.yaml`) sends 100% of `reviews` traffic to `v1` (no star ratings). From there:

```bash
# Weighted canary: 90% v1 / 10% v3 (red stars) — repeat with higher v3 weights to complete the rollout
kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-canary-v3.yaml

# Header-based routing: route end-user "jason" to v2 (black stars), everyone else to v1
kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-user-routing.yaml

# Fault injection: inject a 7s delay for "jason" calling ratings, without touching app code
kubectl apply -f kubernetes-manifests/traffic-management/virtualservice-fault-injection.yaml
```

Refresh `http://<gateway-ip>/productpage` (login as `jason`/any password to exercise the header-matched rules) to see each behavior change live, with zero application redeploys.

### 3. Security — mesh-wide mTLS and zero-trust authorization

`deploy.sh` already applied a `PeerAuthentication` in `STRICT` mode, so every sidecar-to-sidecar call in the mesh must be mutually authenticated — plaintext connections are rejected. Layer identity-based authorization on top:

```bash
kubectl apply -f kubernetes-manifests/security/authorization-policy-ratings.yaml

# Prove it: a pod with no matching ServiceAccount identity gets rejected
kubectl run curl --image=curlimages/curl -n default --rm -it --restart=Never -- \
  curl -sS -o /dev/null -w "%{http_code}\n" http://ratings:9080/ratings/0
# -> 403 RBAC: access denied (only the "bookinfo-reviews" identity is allowed)
```

### 4. Ingress

```bash
GATEWAY_IP=$(kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s "http://${GATEWAY_IP}/productpage" | head -n 5
```

### 5. Observability

This demo wires up the path Microsoft explicitly verifies for the add-on — **Azure Monitor managed Prometheus + Azure Managed Grafana** (see [How is the add-on different from open-source Istio?](https://learn.microsoft.com/azure/aks/istio-about#how-is-the-add-on-different-from-open-source-istio)):

```bash
terraform -chdir=terraform output grafana_endpoint
```

Import Istio's official dashboards (control plane, mesh, service, workload — [istio.io/latest/docs/ops/integrations/grafana](https://istio.io/latest/docs/ops/integrations/grafana/)) into the Grafana workspace and query `istio_requests_total`, `istio_request_duration_milliseconds_bucket`, etc.

**Kiali and Jaeger/distributed tracing are *not* part of the managed add-on** — they're optional, self-managed OSS components you install yourself with Helm, pointed at the add-on's control plane namespace (`aks-istio-system` instead of the upstream default of `istio-system`). Treat this as an advanced follow-up exercise; see [Kiali's Helm install docs](https://kiali.io/docs/installation/installation-guide/) and the [Istio addons](https://github.com/istio/istio/tree/master/samples/addons) sample manifests as starting points.

---

## Limitations of the AKS Istio add-on

Straight from [Microsoft's documented limitations](https://learn.microsoft.com/azure/aks/istio-about#limitations) — know these before you commit to the add-on for a production mesh:

- **No coexistence** with the Open Service Mesh (OSM) add-on or a self-managed/manual Istio install on the same cluster.
- **No virtual nodes** (ACI-backed pods) in the mesh.
- **No Ambient mode** (sidecar-less data plane) yet — Microsoft is contributing upstream, but there's no add-on integration timeline.
- **No multi-cluster mesh** — single-cluster only.
- **No Windows Server containers** in the mesh (upstream Istio itself doesn't support this yet either).
- **Blocked custom resources**: `ProxyConfig`, `WorkloadEntry`, `WorkloadGroup`, `IstioOperator`, `WasmPlugin` cannot be used to customize the add-on.
- **`EnvoyFilter` is allowed but unsupported** — issues caused by a custom `EnvoyFilter` (e.g. a broken Lua script) are outside Microsoft's support scope.
- **No Gateway API / GAMMA support** for mesh traffic management via this add-on (that's the separate App Routing Istio Gateway API feature, ingress-only).
- Only a **subset of `MeshConfig`** fields can be customized; others are unsupported or entirely blocked.
- **No automatic upgrades** — an out-of-date Istio revision is *not* upgraded when the AKS cluster auto-upgrades, and can eventually block the cluster's own auto-upgrade. You must run `az aks mesh upgrade` yourself.
- Only **one internal and one external ingress gateway** are allowed per cluster.
- Ingress/egress gateway **port/protocol customization is not supported** (only annotations and `externalTrafficPolicy`).
- Istio versions are pinned to Microsoft-tested **revisions** (`asm-X-Y`) on a support calendar — you don't get upstream Istio releases the day they ship.

---

## When to choose which

| | **App Routing (Istio) add-on**<br/>[`AKS-Istio-Gateway-API`](../AKS-Istio-Gateway-API/README.md) | **Istio service mesh add-on**<br/>(this demo) | **Self-managed OSS Istio** |
|---|---|---|---|
| Scope | Ingress only | Full mesh: north-south + east-west | Full mesh, fully customizable |
| Sidecars | None | Injected cluster-wide | Injected cluster-wide (or Ambient) |
| Support | Microsoft | Microsoft (within documented limits) | Self-supported / community |
| Upgrade ownership | Microsoft-managed | You trigger it; Microsoft ships tested revisions | Entirely yours, any cadence |
| Customization ceiling | Low | Medium (blocked CRDs, subset of `MeshConfig`) | Full Istio API surface |
| Multi-cluster / Ambient / Gateway API for mesh traffic | N/A | ❌ Not supported | ✅ Supported |
| Operational effort | Minimal | Low-medium | High (you own istiod scaling, CA rotation, CVE patching, CRD lifecycle) |

**Choose the AKS Istio service mesh add-on (this demo) when:**
- You need real mesh features — mTLS everywhere, fine-grained `AuthorizationPolicy`, canary/weighted routing, retries/circuit breaking — on a **single AKS cluster**.
- You want Microsoft to own `istiod` scaling, verified compatibility with your AKS version, and official support, and you can live with the add-on's blocked customizations.
- Your observability needs are satisfied by **Azure Monitor managed Prometheus + Azure Managed Grafana** (the officially verified path), and Kiali/Jaeger (if wanted) can be self-installed as a side project.
- You're fine following Microsoft's Istio revision support calendar rather than tracking every upstream Istio release the day it lands.

**Choose self-managed OSS Istio when:**
- You need **Ambient mode**, **multi-cluster/multi-network mesh**, or Istio's **Gateway API (GAMMA)** support for mesh traffic — none of which the add-on offers today.
- You need to customize `ProxyConfig`, `WorkloadEntry`, `WorkloadGroup`, `IstioOperator`, or `WasmPlugin`, or need full `MeshConfig` control.
- You need the latest upstream Istio minor/patch release immediately, not gated by AKS's revision support calendar.
- You're running a consistent mesh across non-AKS or multi-cloud/hybrid clusters and want one Istio version/toolchain everywhere.
- You're prepared to own istiod scaling, CA/certificate rotation, CVE patching, and CRD lifecycle yourself (or via a vendor other than Microsoft, e.g. Istio-in-a-box distros).

**Choose the App Routing (Istio) add-on instead of both when:** all you need is modern L7 ingress (Gateway API, TLS termination, header/path routing) with **no mesh, no sidecars, and minimal operational surface** — see the [AKS-Istio-Gateway-API](../AKS-Istio-Gateway-API/README.md) demo.

---

## Upgrading the add-on (day 2)

The add-on uses [canary minor-revision upgrades](https://learn.microsoft.com/azure/aks/istio-upgrade): the new revision's control plane runs alongside the existing one, you manually roll data-plane workloads over (relabel namespace + restart pods), verify health, then complete or roll back. In Terraform terms this maps to setting `istio_revisions = ["asm-X-Y", "asm-X-Z"]` (both revisions) during the canary window, then back down to a single-element list once you commit. Patch versions (proxy/istiod image patches within the same revision) roll out automatically via AKS releases; you still restart workloads yourself to pick up the patched sidecar image.

## Cleanup

```bash
./cleanup.sh
```

Prompts for confirmation, then runs `terraform destroy`, removes local state files, and deletes the `.terraform` provider cache — leaving no orphaned Azure resources or stale provider locks behind.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Pods stuck with 1/1 containers instead of 2/2 | Namespace isn't labeled with `istio.io/rev=<revision>` (the generic `istio-injection=enabled` label does **not** work for the add-on), or the pod was created before the label was applied — restart the deployment. |
| `403 RBAC: access denied` on requests that should be allowed | Check the `AuthorizationPolicy` `selector` and `principals` match the caller's actual ServiceAccount (`kubectl get pod <pod> -o jsonpath='{.spec.serviceAccountName}'`). |
| `terraform apply` fails with an unsupported Istio revision/region combo | Run `az aks mesh get-revisions --location <region> -o table` (requires `aks-preview`) and pin a supported `istio_revisions` value in `terraform.tfvars`. |
| Ingress gateway has no external IP | Standard Load Balancer provisioning can take a few minutes; re-run `kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress -w`. |
