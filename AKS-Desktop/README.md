# AKS Desktop with Azure Managed Projects

This demo shows how **AKS Desktop** works and how to use **Azure Managed Projects** to deploy and manage applications. We use an **AKS Automatic** cluster because Managed Projects only work with AKS Automatic.

## What is AKS Desktop?

[AKS Desktop](https://github.com/Azure/aks-desktop/releases) is a desktop application (built on [Headlamp](https://headlamp.dev/)) that provides an application-focused experience for deploying and managing workloads on AKS. Instead of working with raw Kubernetes resources, you work with **Projects** — logical groupings of workloads, services, and configurations.

Key capabilities:

- **Guided application deployment** — deployment wizard that auto-generates Kubernetes manifests aligned to AKS best practices
- **Projects** — application-centric view backed by AKS managed namespaces with built-in network policies, resource quotas, and RBAC
- **Monitoring** — view CPU, memory, logs, scaling, and health status per application via built-in Managed Prometheus metrics
- **Multi-cloud cluster access** — connect to Kubernetes clusters across any cloud
- **kubeconfig management** — sign in with Azure and auto-merge cluster credentials locally

## What are Azure Managed Projects?

In AKS Desktop, a **Project** maps to an [AKS managed namespace](https://learn.microsoft.com/en-us/azure/aks/concepts-managed-namespaces). When you create a Project, AKS Desktop creates a managed namespace with:

- **Network policies** — built-in ingress/egress rules (Allow All, Allow Same Namespace, Deny All)
- **Resource quotas** — CPU and memory request/limit boundaries for the namespace
- **RBAC** — Azure role assignments scoped to the namespace (Reader, Writer, Admin)
- **Adoption/Delete policies** — control how existing namespaces are onboarded and what happens on deletion

This lets platform teams isolate workloads per team while developers get a self-service experience to deploy and monitor their apps.

## Why AKS Automatic?

AKS Desktop is optimized for **AKS Automatic**. While AKS Standard clusters can be added, you won't see the full Project benefits. AKS Automatic includes:

- **Built-in metrics and observability** — Managed Prometheus metrics are pre-configured, enabling AKS Desktop to surface application insights
- **Node Autoprovision (NAP)** — automatically provisions the right VM sizes
- **KEDA** — event-driven autoscaling built-in
- **VPA** — vertical pod autoscaling
- **Azure RBAC** — Kubernetes RBAC backed by Microsoft Entra ID
- **Web App Routing** — managed NGINX ingress add-on

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     AKS Desktop                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ Project A │  │ Project B │  │ Project C │  ...        │
│  │ (ns: app1)│  │ (ns: app2)│  │ (ns: app3)│            │
│  └──────────┘  └──────────┘  └──────────┘              │
│       │              │              │                    │
│       │    Metrics / Logs / Scaling / Map                │
│       └──────────────┼──────────────┘                    │
└──────────────────────┼───────────────────────────────────┘
                       │
          ┌────────────▼────────────┐
          │   AKS Automatic Cluster │
          │   (Managed Namespaces)  │
          └────────────┬────────────┘
                       │
          ┌────────────▼────────────┐
          │  Azure Monitor Workspace│
          │  (Managed Prometheus)   │
          └────────────┬────────────┘
                       │
          ┌────────────▼────────────┐
          │  Azure Managed Grafana  │
          └─────────────────────────┘
```

## What Gets Deployed

| Resource | Description |
|----------|-------------|
| AKS Automatic Cluster | Managed Kubernetes with Automatic SKU and Azure RBAC |
| Azure Monitor Workspace | Managed Prometheus for metrics collection |
| Azure Managed Grafana | Dashboards integrated with Prometheus |
| Log Analytics Workspace | Container Insights log collection |
| Data Collection Rule & Endpoint | Prometheus metrics forwarding pipeline |
| Prometheus Recording Rule Groups | Node, Kubernetes, and UX recording rules for dashboards |
| Role Assignments | Grafana Admin, Monitoring Reader, AKS RBAC Cluster Admin |

## Prerequisites

- [AKS Desktop](https://github.com/Azure/aks-desktop/releases) installed (Windows, Linux, or Mac)
- Azure CLI with `aks-preview` extension (`az extension add --name aks-preview`)
- An active Azure subscription
- Logged in via `az login`
- [k6](https://k6.io/) (optional, for load testing)

## Step 1: Deploy the AKS Automatic Cluster

```bash
chmod +x deploy.sh
./deploy.sh
```

The deploy script will:

1. Create the resource group `rg-aks-automatic-demo` in `swedencentral`
2. Resolve your signed-in user's object ID for Grafana Admin and AKS RBAC roles
3. Deploy all resources using `main.bicepparam`
4. Fetch AKS credentials and print the Grafana URL

## Step 2: Add the Cluster to AKS Desktop

1. Open **AKS Desktop**
2. Select **Home → Sign in with Azure**
3. Select **Add from Azure Subscription**
4. Choose your subscription, select the `aks-automatic-demo` cluster, and click **Register Cluster**

## Step 3: Create a Managed Project

1. In AKS Desktop, select **Create Project**
2. Choose **AKS managed Project**
3. Provide a Project name (e.g. `sample-app`)
4. Configure **Networking Policies** (ingress/egress rules)
5. Set **Compute Quota** (CPU and memory limits for the namespace)
6. Assign **Access** — add users and select roles (Reader, Writer, Admin)
7. Review and click **Create Project**

> **Note:** Register the `ManagedNamespacePreview` feature flag for first-time use.

## Step 4: Deploy an Application

Within your Project, select **Deploy Application**. You can deploy using:

- **Container Image** — paste an ACR image path (`<YourACR>.azurecr.io/<image>:<tag>`) and configure replicas, networking, health checks, resource limits, environment variables, and HPA
- **Kubernetes YAML** — upload or paste a YAML manifest

Alternatively, deploy the sample app via CLI:

```bash
kubectl create namespace sample-app
kubectl apply -f sample-app.yaml
```

This creates:

- A **Deployment** running `aks-helloworld:v1`
- A **ClusterIP Service**
- An **Ingress** using the `webapprouting.kubernetes.azure.com` ingress class
- A **KEDA ScaledObject** that scales 1–10 replicas based on CPU (>50%) and memory (>60%)

## Step 5: Monitor via Project Overview

Once your app is deployed, the **Project Overview** screen in AKS Desktop gives you:

| Feature | Description |
|---------|-------------|
| **Kubernetes Resources** | View all workloads and network config in the Project |
| **Access** | Grant or remove user access to the Project |
| **Map** | Visualize how resources interact (deployments ↔ services) |
| **Logs** | Stream application logs |
| **Metrics** | View CPU, memory, and resource usage (powered by Managed Prometheus) |
| **Scaling** | Configure HPA or manual scaling |
| **Environment Variables** | Manage env vars for the application |

> Metrics may take 5–10 minutes to appear on first deployment as data flows into Managed Prometheus.

## Load Test

Generate traffic to see autoscaling and metrics in action:

```bash
k6 run load-test.js
```

While the test runs, use AKS Desktop's **Metrics** tab or the Grafana dashboard to observe live CPU/memory usage, pod scaling events, and network traffic.

## Viewing Grafana Dashboards

Open the Grafana URL printed by the deploy script. Built-in dashboards include:

- **Kubernetes / Compute Resources / Cluster** — overall cluster CPU and memory
- **Kubernetes / Compute Resources / Namespace (Pods)** — per-namespace breakdown
- **Kubernetes / Networking** — network receive/transmit and drop rates
- **Node Exporter** — node-level CPU, memory, and disk metrics

The UX recording rules also power the Azure Portal's **Monitoring → Insights** blade for the AKS cluster.

## Cleanup

```bash
chmod +x cleanup.sh
./cleanup.sh
```

This removes the kubeconfig entries from your local machine and deletes the resource group.

## References

- [AKS Desktop overview](https://learn.microsoft.com/en-us/azure/aks/aks-desktop-overview)
- [Deploy an application with AKS Desktop](https://learn.microsoft.com/en-us/azure/aks/aks-desktop-app)
- [Managed namespaces in AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-managed-namespaces)
- [AKS Desktop GitHub releases](https://github.com/Azure/aks-desktop/releases)
