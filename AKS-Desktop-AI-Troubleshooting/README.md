# AKS Desktop AI Troubleshooting Demo

This demo is intentionally isolated from the existing AKS Desktop sample so you can run it as a separate live troubleshooting exercise.

## Goal

Create a small AKS Automatic cluster, deploy a few intentionally broken workloads, and use AKS Desktop plus AI assistance to troubleshoot the symptoms and fix the app.

## What gets deployed

- One default AKS cluster (standard managed cluster, not AKS Automatic)
- A dedicated namespace called `ai-demo`
- Three workload scenarios:
  - `broken-image` → image pull failure
  - `crash-loop` → startup command exits immediately
  - `pending-pod` → node selector prevents scheduling

## Prerequisites

- Azure CLI logged in
- An Azure subscription with permissions to create resource groups and AKS clusters
- AKS Desktop installed locally
- Optional: `kubectl`

## Deploy the cluster

From this folder:

```bash
chmod +x deploy.sh
./deploy.sh
```

The script creates a resource group and deploys the AKS cluster using the Bicep template.

## Connect to AKS Desktop

1. Open AKS Desktop
2. Sign in with Azure
3. Add the cluster from your subscription
4. Open the cluster and create a project or select the namespace view

## Deploy the broken app

```bash
kubectl create namespace ai-demo
kubectl apply -f broken-app-demo.yaml
```

## Suggested AI troubleshooting prompts

```text
Why is the broken-image pod stuck in ImagePullBackOff?
Show me the pod events for crash-loop and identify the root cause.
Why is the pending-pod deployment never scheduled?
Which config issue caused the app to exit immediately?
What is the quickest safe fix for all three workloads?
```

## Fix the workload

```bash
kubectl apply -f fixed-app-demo.yaml
```

This replaces the broken image, fixes the crash loop startup command, and removes the invalid node selector so the app comes up cleanly.

## Cleanup

```bash
chmod +x cleanup.sh
./cleanup.sh
```

## Demo narrative

This is a good live demo for showing how AI assistance can shorten the time to root cause in Kubernetes:

- the workload appears unhealthy in AKS Desktop
- the AI assistant reads the events and logs
- the root cause is identified quickly
- the corrected manifest is applied
- the workload recovers and becomes healthy
