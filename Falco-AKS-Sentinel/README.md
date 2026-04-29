# Falco Runtime Security on AKS → Microsoft Sentinel

End-to-end demo that runs **OSS [Falco](https://falco.org)** as a DaemonSet on AKS, ships every alert through **falcosidekick** to a **Logic App webhook**, lands the events in a **Log Analytics** custom table (`FalcoAlerts_CL`), and lets **Microsoft Sentinel** turn them into **incidents** via a scheduled analytics rule.

## Architecture

```
┌───────────────────────────┐
│  AKS workload (attacker)  │
└─────────────┬─────────────┘
              │ syscalls
              ▼
┌───────────────────────────┐     stdout/JSON
│  Falco DaemonSet (eBPF)   │ ──────────────┐
└─────────────┬─────────────┘               │
              │ alerts                       ▼
              ▼                    Container Insights
┌───────────────────────────┐
│  falcosidekick (webhook)  │
└─────────────┬─────────────┘
              │ HTTPS POST (JSON)
              ▼
┌───────────────────────────┐
│ Azure Logic App (HTTP)    │
│  └─ Send Data to LAW      │
└─────────────┬─────────────┘
              ▼
┌───────────────────────────┐
│  Log Analytics            │
│  Table: FalcoAlerts_CL    │
└─────────────┬─────────────┘
              ▼
┌───────────────────────────┐
│ Microsoft Sentinel        │
│  - Scheduled analytic     │
│  - Incident creation      │
└───────────────────────────┘
```

## What gets deployed

| Resource | Purpose |
|---|---|
| `Microsoft.OperationalInsights/workspaces` | Log Analytics workspace (Sentinel-enabled) |
| `Microsoft.OperationsManagement/solutions` | Microsoft Sentinel onboarding |
| `Microsoft.Web/connections` | Azure Log Analytics Data Collector API connection |
| `Microsoft.Logic/workflows` | HTTP webhook → ingest into `FalcoAlerts_CL` |
| `Microsoft.ContainerService/managedClusters` | Small AKS cluster (Cilium overlay, OMS addon) |
| `Microsoft.SecurityInsights/alertRules` | Scheduled analytic rule that creates incidents |

Falco itself (DaemonSet + falcosidekick + UI) is installed by `deploy.sh` via the official Helm chart.

## Prerequisites

- Azure CLI ≥ `2.60` (`az login` already done)
- `kubectl`, `helm`, `jq`
- Subscription owner/contributor + permission to create Log Analytics workspaces
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
2. `az deployment group create` against [main.bicep](main.bicep).
3. Read the Logic App's HTTP-trigger callback URL.
4. `az aks get-credentials`.
5. `helm install` Falco + falcosidekick, injecting the webhook URL.

## Run the demo

```bash
# 1) Deploy a privileged attacker pod
kubectl apply -f sample-attacks/attack-pod.yaml

# 2) Generate suspicious behaviour (reads /etc/shadow, writes /etc, etc.)
./sample-attacks/trigger-events.sh

# 3) Stream Falco detections live
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# 4) (Optional) Open falcosidekick UI
kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802
# Browse: http://localhost:2802
```

## Verify in Log Analytics & Sentinel

The first event creates the custom table — expect **2–10 minutes** of ingestion latency the first time.

```bash
WS_ID=$(az monitor log-analytics workspace show \
  -g "$RESOURCE_GROUP" -n falcosec-law --query customerId -o tsv)

az monitor log-analytics query -w "$WS_ID" \
  --analytics-query "FalcoAlerts_CL | take 20" -o table
```

KQL examples to run in **Sentinel → Logs**:

```kusto
// All Falco alerts in the last hour
FalcoAlerts_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, priority_s, rule_s, output_s, hostname_s
| order by TimeGenerated desc
```

```kusto
// Top firing rules
FalcoAlerts_CL
| summarize Count = count() by rule_s, priority_s
| order by Count desc
```

Open **Microsoft Sentinel → Incidents**. The scheduled rule *"Falco — Runtime Security Alert (AKS)"* runs every 5 minutes and creates incidents for `Critical | Error | Warning | Emergency | Alert` priorities.

## How the integration works

- **falcosidekick** is configured via [falco-values.yaml.tpl](falco-values.yaml.tpl) with a single `webhook` output. `deploy.sh` substitutes `__WEBHOOK_URL__` with the Logic App's listable callback URL (it includes a SAS-style signature; treat it as a secret).
- The **Logic App** uses the built-in `azureloganalyticsdatacollector` connector — no HMAC signing needed in the workflow definition. Each event is POSTed to `/api/logs` with header `Log-Type: FalcoAlerts`, which Log Analytics surfaces as `FalcoAlerts_CL` (`_CL` is appended automatically for HTTP Data Collector tables).
- The **Sentinel analytic rule** queries that table every 5 minutes and creates incidents using `groupingConfiguration.matchingMethod = AllEntities` so repeat noise from the same rule/host gets grouped.

## Files

| File | What it is |
|---|---|
| [main.bicep](main.bicep) | All Azure resources |
| [main.bicepparam](main.bicepparam) | Parameter values (region, sizes) |
| [deploy.sh](deploy.sh) | Bicep + Helm bootstrapper |
| [cleanup.sh](cleanup.sh) | Tears the demo down |
| [falco-values.yaml.tpl](falco-values.yaml.tpl) | Helm values template (webhook placeholder) |
| [sample-attacks/attack-pod.yaml](sample-attacks/attack-pod.yaml) | Privileged pod used as the target |
| [sample-attacks/trigger-events.sh](sample-attacks/trigger-events.sh) | Generates the suspicious behaviours |

## Cleanup

```bash
./cleanup.sh
```

This deletes the resource group and the AKS node resource group asynchronously.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FalcoAlerts_CL` not appearing | Wait up to 10 minutes after the first event. Verify Logic App run history shows `200 OK` from the connector. |
| Logic App run fails with `401` | Re-deploy — the API connection's shared key is set from `workspace.listKeys()` at deploy time. |
| Falco pods `CrashLoopBackOff` | Try `driver.kind: ebpf` (legacy) instead of `modern_ebpf` in the values template; some kernels need it. |
| No Sentinel incidents | Confirm the rule is **enabled** in *Sentinel → Analytics*; check the query manually in *Logs*. |
