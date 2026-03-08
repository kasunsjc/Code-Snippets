# AKS & Kubernetes Troubleshooting — Custom GitHub Copilot Agent

A custom GitHub Copilot agent specialized in Azure Kubernetes Service (AKS) and Kubernetes troubleshooting. This agent acts as an expert SRE to help you diagnose, troubleshoot, and resolve incidents quickly.

## Project Structure

```
.github/
├── agents/
│   └── aks-troubleshooter.md      # Custom Copilot agent definition
├── prompts/
│   ├── aks-troubleshoot.prompt.md  # AKS-specific troubleshooting prompt
│   └── k8s-troubleshoot.prompt.md  # General Kubernetes troubleshooting prompt
└── copilot-instructions.md         # Global Copilot instructions for the repo
```

## What's Included

### Custom Agent — `aks-troubleshooter`

The agent is defined in `.github/agents/aks-troubleshooter.md` and provides:

- **Systematic 5-step troubleshooting workflow**: Triage → Gather Evidence → Diagnose → Remediate → Verify & Prevent
- **8 issue categories**: Pod/Workload, Networking, Storage, Node/Cluster, Control Plane, Auth & RBAC, Upgrades, Performance
- **Safety-first approach**: Destructive commands are always flagged with ⚠️ warnings
- **AKS-specific knowledge**: Architecture, networking models, identity, key features, CLI commands
- **Structured incident response** template for consistent analysis

### Reusable Prompts

| Prompt | Description |
|--------|-------------|
| `aks-troubleshoot` | AKS-specific diagnostics: node health, ACR integration, networking, upgrades, scaling |
| `k8s-troubleshoot` | General Kubernetes: pods, services, storage, RBAC, Helm, Jobs, ConfigMaps |

### Copilot Instructions

The `.github/copilot-instructions.md` file ensures that **all** Copilot interactions within this repo follow the SRE troubleshooting methodology with safety-first principles.

## How to Use

### Using the Custom Agent

In VS Code with GitHub Copilot Chat, invoke the agent by typing:

```
@aks-troubleshooter my pods are stuck in CrashLoopBackOff in the production namespace
```

The agent will:
1. Classify the issue (Pod/Workload)
2. Provide diagnostic commands to run
3. Analyze the output and identify root causes
4. Suggest remediation steps with exact commands
5. Recommend verification and preventive measures

### Using the Prompts

Reference prompts in Copilot Chat:

```
#aks-troubleshoot I need to debug a node that went NotReady
#k8s-troubleshoot My service endpoint is showing no IPs
```

### Example Queries

```
@aks-troubleshooter pods stuck in Pending state after scaling the deployment to 20 replicas
@aks-troubleshooter LoadBalancer service external IP is not being assigned
@aks-troubleshooter DNS resolution is failing inside pods
@aks-troubleshooter AKS cluster upgrade from 1.28 to 1.29 is stuck
@aks-troubleshooter Getting "Forbidden" errors when deploying with a service account
@aks-troubleshooter HPA is not scaling up despite high CPU usage
@aks-troubleshooter ImagePullBackOff when pulling from our private ACR
```

## Covered Troubleshooting Scenarios

| Category | Scenarios |
|----------|-----------|
| **Pod/Workload** | CrashLoopBackOff, ImagePullBackOff, OOMKilled, Pending, Init container failures |
| **Networking** | DNS failures, Service not reachable, LoadBalancer pending, Ingress issues, Network Policy |
| **Storage** | PVC not binding, disk attach/detach errors, CSI driver issues |
| **Node/Cluster** | Node NotReady, scaling failures, VM allocation issues |
| **Control Plane** | API server latency, webhook failures |
| **Auth & RBAC** | Forbidden errors, service account issues, Entra ID integration |
| **Upgrades** | Failed upgrades, PDB blocking drain, deprecated APIs, version skew |
| **Performance** | High CPU/memory, HPA not scaling, throttling |

## Prerequisites

- [VS Code](https://code.visualstudio.com/) with [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) extension
- GitHub Copilot Chat enabled
- `kubectl` configured with cluster access
- `az` CLI installed (for AKS-specific commands)
