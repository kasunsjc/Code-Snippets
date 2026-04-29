# Falco Runtime Security on AKS → Microsoft Sentinel

End-to-end demo that runs **OSS [Falco](https://falco.org)** as a DaemonSet on AKS, ships every alert through **falcosidekick** to a **Logic App** webhook, lands the events in a **Log Analytics** custom table (`FalcoLogs_CL`), and lets **Microsoft Sentinel** turn them into **incidents** via 5 scheduled analytics rules.

> Inspired by and aligned with [`kasunsjc/aks-labs/apps/falco`](https://github.com/kasunsjc/aks-labs/tree/main/apps/falco) and the [`deploy-falco.yml`](https://github.com/kasunsjc/aks-labs/blob/main/.github/workflows/deploy-falco.yml) workflow. Custom Falco rules, Sentinel analytics rules, and Helm values are reused directly from that repository so KQL queries reference the exact same field names (`output_fields_k8s_pod_name_s`, `priority_s`, `rule_s`, …).

## Architecture

```
┌───────────────────────────┐
│  AKS workload (attacker)  │
└─────────────┬─────────────┘
              │ syscalls
              ▼
┌───────────────────────────┐
│  Falco DaemonSet (eBPF)   │ + custom AKS rules:
│                           │   - Unauthorized Process
│                           │   - Sensitive File Access
│                           │   - Kubernetes Secret Access
│                           │   - Package Management
│                           │   - Reverse Shell
└─────────────┬─────────────┘
              │ HTTP (JSON)
              ▼
┌───────────────────────────┐
│  falcosidekick → webhook  │
└─────────────┬─────────────┘
              │ HTTPS POST
              ▼
┌───────────────────────────┐
│ Azure Logic App           │
│  trigger:                 │
│  When_an_HTTP_request_    │
│    is_received            │
│  action: Send Data to LAW │
└─────────────┬─────────────┘
              ▼
┌───────────────────────────┐
│  Log Analytics            │
│  Table: FalcoLogs_CL      │
└─────────────┬─────────────┘
              ▼
┌───────────────────────────┐
│ Microsoft Sentinel        │
│  5 scheduled rules →      │
│  incidents                │
└───────────────────────────┘
```

## What gets deployed

| Resource | Purpose |
|---|---|
| `Microsoft.OperationalInsights/workspaces` | Log Analytics workspace (Sentinel-enabled) |
| `Microsoft.OperationsManagement/solutions` | Microsoft Sentinel onboarding |
| `Microsoft.Web/connections` | Azure Log Analytics Data Collector API connection |
| `Microsoft.Logic/workflows` | HTTP webhook → ingest into `FalcoLogs_CL` |
| `Microsoft.ContainerService/managedClusters` | Small AKS cluster (Cilium overlay, OMS addon, custom node RG `rg-falcosec-nodes`) |
| `Microsoft.SecurityInsights/alertRules` × 5 | All scheduled rules from [sentinel-analytics-rules.json](sentinel-analytics-rules.json) |

Falco itself (DaemonSet + falcosidekick) is installed by `deploy.sh` via the official Helm chart using [values.yaml](values.yaml).

## Sentinel analytics rules (created by Bicep)

| Rule | Severity | Detects |
|---|---|---|
| Falco — Critical Security Alert | High | Any `priority == Critical` event |
| Falco — Suspicious Process Execution | Medium | Rules containing `Process` / `Execution` |
| Falco — Sensitive File Access | High | `/etc/shadow`, SSH keys, K8s secrets |
| Falco — Reverse Shell Detection | High | `bash -i`, `nc -e`, scripted reverse shells |
| Falco — Multiple Alerts from Same Pod | High | ≥5 alerts from the same pod in 10 minutes |

## Prerequisites

- Azure CLI ≥ `2.60` (`az login` already done)
- `kubectl`, `helm`, `jq`, `envsubst` (gettext)
- Subscription contributor + permission to create Log Analytics workspaces and Sentinel alert rules
- ~12 minutes for end-to-end provisioning

## Deploy

```bash
cd Falco-AKS-Sentinel
chmod +x deploy.sh cleanup.sh sample-attacks/trigger-events.sh

# Optional overrides
export RESOURCE_GROUP=rg-falco-sentinel-demo
export LOCATION=northeurope
export PROJECT_NAME=falcosec

./deploy.sh
```

`deploy.sh` will:

1. Create the resource group.
2. `az deployment group create` against [main.bicep](main.bicep) (loads the rule list from JSON via `loadJsonContent`).
3. Read the Logic App callback URL for trigger `When_an_HTTP_request_is_received`.
4. `az aks get-credentials`, `kubectl apply -f namespace.yaml`.
5. `envsubst` the webhook URL into [values.yaml](values.yaml), then `helm upgrade --install`.

## Run the demo

```bash
# 1) Deploy a privileged attacker pod
kubectl apply -f sample-attacks/attack-pod.yaml

# 2) Generate suspicious behaviour (reads /etc/shadow, writes /etc, exec shell, package mgr)
./sample-attacks/trigger-events.sh

# 3) Stream Falco detections live
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# 4) Watch falcosidekick forward to Logic App
kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick -f
```

## Verify in Log Analytics & Sentinel

The first event creates the `FalcoLogs_CL` custom table — expect **2–10 minutes** of ingestion latency the first time.

```bash
WS_ID=$(az monitor log-analytics workspace show \
  -g "$RESOURCE_GROUP" -n falcosec-law --query customerId -o tsv)

az monitor log-analytics query -w "$WS_ID" \
  --analytics-query "FalcoLogs_CL | take 20" -o table
```

KQL examples to run in **Sentinel → Logs**:

```kusto
// All Falco alerts in the last hour
FalcoLogs_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, priority_s, rule_s, output_s,
          PodName = output_fields_k8s_pod_name_s,
          Namespace = output_fields_k8s_ns_name_s
| order by TimeGenerated desc
```

```kusto
// Top firing rules
FalcoLogs_CL
| summarize Count = count() by rule_s, priority_s
| order by Count desc
```

Open **Microsoft Sentinel → Incidents**. Each rule runs every 5–10 minutes and creates incidents with grouping enabled (so repeat noise from the same pod gets bundled).

## How the integration works

- **values.yaml** (taken from `aks-labs`) installs the `falcosecurity/falco` chart with the modern eBPF driver, falcosidekick enabled, and a `webhook` output addressed by `${LOGIC_APP_WEBHOOK_URL}`. `deploy.sh` runs `envsubst` over it before `helm upgrade`. It also injects 5 custom AKS-focused rules under `customRules.aks-custom-rules.yaml`.
- The **Logic App** uses the built-in `azureloganalyticsdatacollector` connector — no HMAC signing in the workflow definition. Each event is POSTed to `/api/logs` with header `Log-Type: FalcoLogs`, which Log Analytics surfaces as `FalcoLogs_CL` (`_CL` is appended automatically).
- Trigger name `When_an_HTTP_request_is_received` is the default Logic App designer name and matches the `listCallbackUrl` path used by the upstream `deploy-falco.yml` workflow.
- The **Bicep** template loads [sentinel-analytics-rules.json](sentinel-analytics-rules.json) at compile time via `loadJsonContent()` and creates one `Microsoft.SecurityInsights/alertRules` resource per entry inside a `for` loop — so editing the JSON and redeploying is enough to evolve detections.

## Files

| File | What it is |
|---|---|
| [main.bicep](main.bicep) | All Azure resources |
| [main.bicepparam](main.bicepparam) | Parameter values (region, sizes) |
| [deploy.sh](deploy.sh) | Bicep + Helm bootstrapper |
| [cleanup.sh](cleanup.sh) | Tears the demo down |
| [namespace.yaml](namespace.yaml) | Falco namespace manifest |
| [values.yaml](values.yaml) | Helm values + custom Falco rules (envsubst placeholder) |
| [sentinel-analytics-rules.json](sentinel-analytics-rules.json) | 5 Sentinel scheduled rules |
| [sample-attacks/attack-pod.yaml](sample-attacks/attack-pod.yaml) | Privileged pod used as the target |
| [sample-attacks/trigger-events.sh](sample-attacks/trigger-events.sh) | Generates suspicious behaviour |

## Cleanup

```bash
./cleanup.sh
```

Deletes the resource group and the AKS node resource group asynchronously.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FalcoLogs_CL` not appearing | Wait up to 10 minutes after the first event. In *Logic App → Run history* you should see `200 OK` from the connector. |
| Logic App run fails with `401` | Re-deploy — the API connection's shared key is set from `workspace.listKeys()` at deploy time. |
| Falco pods `CrashLoopBackOff` | Try `driver.kind: ebpf` (legacy) instead of `modern_ebpf` in [values.yaml](values.yaml); some kernels need it. |
| No Sentinel incidents | Confirm the rule is **enabled** in *Sentinel → Analytics*; run the query manually in *Logs* to verify it returns rows. |
| `az sentinel alert-rule list` fails | `az extension add --name sentinel --allow-preview true` (the Sentinel CLI extension is required). |
