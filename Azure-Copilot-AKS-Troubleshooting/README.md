# Troubleshooting AKS with Microsoft Copilot in Azure

## Overview

This demo shows how to use **Microsoft Copilot in Azure** (Azure Portal Copilot) to troubleshoot common issues in Azure Kubernetes Service (AKS) clusters. Instead of manually running `kubectl` commands and digging through logs, you can ask Copilot natural language questions directly in the Azure Portal and get actionable insights.

## What is Microsoft Copilot in Azure?

Microsoft Copilot in Azure is an AI-powered assistant integrated into the Azure Portal that helps you:

- **Diagnose cluster issues** — Identify pod failures, node problems, and resource constraints
- **Analyze logs and events** — Query Kubernetes events and container logs with natural language
- **Get recommended fixes** — Receive step-by-step remediation guidance
- **Understand resource health** — Check cluster, node pool, and workload health status
- **Optimize configurations** — Get suggestions for resource limits, scaling, and best practices

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Infrastructure Deployment](#infrastructure-deployment)
3. [Deploy Sample Applications](#deploy-sample-applications)
4. [Using Copilot for Troubleshooting](#using-copilot-for-troubleshooting)
5. [Prompt Catalog](#prompt-catalog)
6. [Cleanup](#cleanup)

---

## Prerequisites

- **Azure Subscription** with Copilot in Azure enabled
- **Azure CLI 2.76+** — `az version`
- **kubectl** — Kubernetes CLI
- **Contributor** role on the subscription or resource group

### Enable Copilot in Azure

1. Go to the [Azure Portal](https://portal.azure.com)
2. Click the **Copilot** icon in the toolbar (top bar)
3. If not enabled, an admin must enable it under **Settings > Copilot** in the Azure Portal

---

## Infrastructure Deployment

### Deploy AKS Cluster

```bash
# Clone the repo and navigate to this folder
cd Azure-Copilot-AKS-Troubleshooting

# Deploy infrastructure
chmod +x deploy.sh
./deploy.sh
```

This deploys:
- A resource group `rg-copilot-aks-demo`
- An AKS cluster with monitoring enabled (Container Insights)
- Log Analytics workspace for diagnostics

### Connect to the Cluster

```bash
az aks get-credentials \
  --resource-group rg-copilot-aks-demo \
  --name copilot-aks-demo
```

---

## Deploy Sample Applications

Deploy intentionally broken applications to create troubleshooting scenarios:

```bash
cd sample-apps
chmod +x deploy-samples.sh
./deploy-samples.sh
```

This deploys several workloads with common issues:

| # | Application | Issue | Expected State |
|---|------------|-------|----------------|
| 1 | `crashloop-app` | Missing required env var | CrashLoopBackOff |
| 2 | `oom-killed-app` | Memory limit too low | OOMKilled |
| 3 | `image-pull-error` | Invalid container image | ImagePullBackOff |
| 4 | `pending-pod` | Excessive resource requests | Pending |
| 5 | `failing-probe-app` | Bad liveness probe | CrashLoopBackOff |
| 6 | `dns-resolution-app` | Service name typo | Connection errors |
| 7 | `wrong-port-app` | Container port mismatch | Connection refused |
| 8 | `readonly-fs-app` | Read-only filesystem write attempt | CrashLoopBackOff |

> **Wait 2-3 minutes** after deploying for issues to manifest before using Copilot.

---

## Using Copilot for Troubleshooting

### How to Access

1. Navigate to your **AKS cluster** in the Azure Portal
2. Click the **Copilot** button in the top toolbar
3. Type your question in natural language

### Workflow

```
1. Deploy broken apps  →  2. Open Azure Portal  →  3. Navigate to AKS cluster
       ↓                                                      ↓
4. Open Copilot        →  5. Ask question        →  6. Follow recommendations
```

---

## Prompt Catalog

Below are ready-to-use prompts organized by troubleshooting category. Copy and paste these directly into Copilot in Azure.

### Cluster Health & Overview

```
What is the current health status of my AKS cluster?
```

```
Are there any issues with the nodes in my AKS cluster?
```

```
Show me the recent events and warnings in my AKS cluster.
```

```
Is my AKS cluster running the latest supported Kubernetes version?
```

```
Are there any recommended actions for my AKS cluster?
```

### Pod Troubleshooting

```
Why are pods in the troubleshooting-demos namespace failing?
```

```
What is causing the CrashLoopBackOff status for the crashloop-app pod?
```

```
Why is the oom-killed-app pod being OOMKilled and how do I fix it?
```

```
Why is the image-pull-error pod stuck in ImagePullBackOff?
```

```
Why is the pending-pod stuck in Pending state and not being scheduled?
```

```
Show me the logs for the failing-probe-app pod.
```

```
How do I fix a pod that keeps restarting due to a failed liveness probe?
```

### Networking & Connectivity

```
Are there any network connectivity issues in my AKS cluster?
```

```
Why can't my dns-resolution-app pod connect to the backend service?
```

```
How do I troubleshoot DNS resolution failures in my AKS cluster?
```

```
Is there a network policy blocking traffic to my pods?
```

```
How do I check if my AKS cluster's DNS is working correctly?
```

### Scaling & Performance

```
Is my AKS cluster running out of resources?
```

```
Which pods are consuming the most CPU and memory?
```

```
Should I scale up my node pool based on current resource usage?
```

```
How do I enable the cluster autoscaler for my AKS cluster?
```

```
What are the recommended resource requests and limits for my workloads?
```

### Security & Compliance

```
Are there any security recommendations for my AKS cluster?
```

```
Is my AKS cluster compliant with Azure security best practices?
```

```
Are there any pods running as root that shouldn't be?
```

```
How do I enable Microsoft Defender for my AKS cluster?
```

```
What RBAC permissions are configured on my cluster?
```

### Diagnostics & Logs

```
Show me container logs for pods in the troubleshooting-demos namespace.
```

```
What Kubernetes events occurred in the last hour?
```

```
Are there any failed deployments in my cluster?
```

```
Help me run a diagnostic check on my AKS cluster.
```

```
Query the container insights logs for error events in the last 24 hours.
```

### Advanced Troubleshooting

```
My application is responding slowly. Help me identify the bottleneck in my AKS cluster.
```

```
I'm getting connection refused errors when accessing my service. What could be wrong?
```

```
Help me understand why my deployment rollout is stuck.
```

```
Walk me through troubleshooting a pod that can't mount its persistent volume.
```

```
How do I diagnose intermittent pod failures in my cluster?
```

---

## Demo Walkthrough

### Scenario 1: Diagnose CrashLoopBackOff

1. Open Copilot in Azure Portal
2. Ask: `Why are pods crashing in the troubleshooting-demos namespace?`
3. Copilot analyzes events, logs, and pod status
4. Follow the remediation steps provided

### Scenario 2: Investigate OOMKilled Pods

1. Ask: `Why is the oom-killed-app pod being OOMKilled?`
2. Copilot checks memory limits and actual usage
3. Apply the suggested memory limit increase

### Scenario 3: Fix ImagePullBackOff

1. Ask: `Why can't my cluster pull the image for image-pull-error pod?`
2. Copilot identifies the invalid image reference
3. Update the deployment with the correct image

### Scenario 4: Resolve Pending Pods

1. Ask: `Why is the pending-pod not being scheduled?`
2. Copilot checks node capacity and resource requests
3. Adjust resource requests or scale the node pool

---

## Cleanup

```bash
chmod +x cleanup.sh
./cleanup.sh
```

This removes the entire resource group and all associated resources.

---

## Tips for Using Copilot Effectively

- **Be specific** — Include namespace, pod name, or resource name in your prompts
- **Use follow-ups** — Copilot maintains conversation context, so ask follow-up questions
- **Reference the portal** — Copilot can reference the resource you're currently viewing
- **Ask for KQL queries** — Copilot can generate Log Analytics queries for deeper analysis
- **Request step-by-step** — Ask "walk me through" for guided troubleshooting

---

## Related Resources

- [Microsoft Copilot in Azure Documentation](https://learn.microsoft.com/en-us/azure/copilot/)
- [AKS Troubleshooting Guide](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)
- [Container Insights Overview](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)
