# Agentic CLI for Azure Kubernetes Service (AKS)

> ⚠️ **Preview Feature** - This is an experimental Azure CLI extension currently in preview. Not recommended for production environments.

## Overview

The Agentic CLI brings AI-powered troubleshooting directly to your AKS clusters. Instead of manually running multiple kubectl commands and piecing together cluster issues, simply ask questions in natural language and let AI analyze your cluster state, identify problems, and suggest solutions.

Think of it as having an expert Kubernetes engineer available 24/7, powered by Large Language Models like GPT-4o or Claude Sonnet.

## What Makes It Special?

- **Natural Language Interface**: Ask questions like "Why is my pod crashing?" instead of memorizing complex kubectl commands
- **Contextual Analysis**: The agent maintains conversation context, allowing follow-up questions without repeating cluster details
- **Multi-Source Intelligence**: Integrates with Kubernetes APIs, logs, metrics, and Azure Resource Manager for comprehensive insights
- **Interactive Troubleshooting**: Suggests next steps and explores different debugging paths based on your responses

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Infrastructure Deployment](#infrastructure-deployment)
3. [Install Agentic CLI Extension](#install-agentic-cli-extension)
4. [Configure Azure OpenAI](#configure-azure-openai)
5. [Using the Agent](#using-the-agent)
6. [Deploy Sample Applications](#deploy-sample-applications)
7. [Advanced Configuration](#advanced-configuration)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)
10. [Cleanup](#cleanup)

---

## Prerequisites

Before getting started, ensure you have:

- **Azure CLI 2.76+** - Check your version with `az version`
- **Azure Subscription** - With permissions to create resources
- **kubectl** - Kubernetes command-line tool
- **LLM API Access** - API key from Azure OpenAI (recommended), OpenAI, or compatible providers
- **Git** (optional) - To clone this repository

### Verify Prerequisites

```bash
# Check Azure CLI version
az version

# Login to Azure
az login

# Set your subscription
az account set --subscription <subscription-id>
```

---

## Infrastructure Deployment

This repository includes Bicep templates to deploy all required infrastructure for the Agentic CLI demo.

### What Gets Deployed

The included Bicep templates create:

- **AKS Cluster** - 2-node cluster with autoscaling (1-5 nodes), Kubernetes 1.31.2
- **Azure OpenAI** - GPT-4o model deployment with 150K TPM
- **Azure Container Registry** - For container image storage
- **Virtual Network** - Network isolation for AKS
- **Log Analytics** - Container Insights and monitoring
- **Role Assignments** - ACR pull permissions for AKS

### Step 1: Customize Deployment Parameters

Review and customize parameters in `main.bicepparam`:

```bicep
param namePrefix = 'aksagent'      // Change to your preferred prefix
param environment = 'dev'           // dev, test, or prod
param location = 'eastus'           // Your preferred Azure region
param nodeCount = 2                 // Initial node count
param kubernetesVersion = '1.31.2'  // Kubernetes version
```

### Step 2: Deploy Infrastructure

Run the automated deployment script:

```bash
./deploy.sh
```

The script will:
- Create the resource group `rg-aksagent-demo`
- Deploy all infrastructure (takes 10-15 minutes)
- Configure kubectl access to the cluster
- Retrieve Azure OpenAI credentials
- Display all connection details

**Save the output!** You'll need the Azure OpenAI details for the next step.

### Alternative: Manual Deployment

If you prefer manual deployment:

```bash
# Create resource group
az group create --name rg-aksagent-demo --location eastus

# Deploy infrastructure
az deployment group create \
  --name aksagent-deployment \
  --resource-group rg-aksagent-demo \
  --template-file main.bicep \
  --parameters main.bicepparam

# Get AKS credentials
az aks get-credentials \
  --resource-group rg-aksagent-demo \
  --name <aks-cluster-name> \
  --overwrite-existing

# Verify cluster access
kubectl get nodes
```

### Common Deployment Issues

<details>
<summary><strong>Kubernetes Version Not Supported</strong></summary>

If you get an error about unsupported Kubernetes version:

```bash
# Check available versions for your region
./check-k8s-versions.sh eastus

# Update main.bicepparam with a supported version
param kubernetesVersion = '1.31.2'  # Use a version from the list
```
</details>

<details>
<summary><strong>Deployment Not Found Error</strong></summary>

If the deployment script can't find outputs, wait for deployment to complete:

```bash
# Check deployment status
az deployment group list --resource-group rg-aksagent-demo --output table

# Once completed, manually get outputs
az deployment group show \
  --name <deployment-name> \
  --resource-group rg-aksagent-demo \
  --query properties.outputs
```
</details>

<details>
<summary><strong>Azure OpenAI Quota Issues</strong></summary>

If deployment fails due to quota limits:
- Request quota increase in Azure Portal
- Reduce `openAiModelCapacity` in main.bicepparam
- Try a different region with availability
</details>

### Cost Estimation

Approximate monthly costs (based on East US pricing):

| Resource | SKU | Estimated Cost |
|----------|-----|----------------|
| AKS | 2x Standard_D4s_v3 nodes | ~$280/month |
| Azure OpenAI | S0 with 150K TPM | ~$60/month (usage-based) |
| Container Registry | Standard | ~$20/month |
| Log Analytics | Pay-as-you-go | ~$10/month |
| **Total** | | **~$370/month** |

💡 **Tip**: Delete resources when not in use to avoid charges. The deployment script makes it easy to recreate everything.

---

## Install Agentic CLI Extension

### Step 1: Install the Extension

The extension installs as an Azure CLI plugin. Installation typically takes 5-10 minutes:

```bash
# Fresh installation
az extension add --name aks-agent --debug

# Update existing installation (if already installed)
az extension update --name aks-agent --debug
```

### Step 2: Verify Installation

```bash
# Check extension is installed
az extension list | grep aks-agent

# View help
az aks agent --help
```

You should see the `aks-agent` extension with version information.

---

## Configure Azure OpenAI

### Step 1: Initialize the Agent

Run the initialization wizard to set up your LLM connection:

```bash
az aks agent-init
```

### Step 2: Enter Configuration Details

You'll be prompted to enter:

1. **LLM Provider**: Select `1` for Azure OpenAI (recommended)
2. **Model Name**: Your deployment name (e.g., `gpt-4o`)
3. **API Key**: From the deployment script output or Azure Portal
4. **API Base URL**: Format: `https://<resource-name>.openai.azure.com/`
5. **API Version**: Leave default or use `2024-08-01-preview`

Example configuration:

```
Welcome to AKS Agent LLM configuration setup. Type '/exit' to exit.
 1. Azure Open AI
 2. openai
 3. anthropic
 4. gemini
 5. openai_compatible
Enter the number of your LLM provider: 1
Your selected provider: azure
Enter value for MODEL_NAME: gpt-4o
Enter your API key: <your-api-key-here>
Enter value for AZURE_API_BASE: https://aksagent-openai-dev-xxxxx.openai.azure.com/
Enter value for AZURE_API_VERSION: 2024-08-01-preview
LLM configuration setup successfully.
```

💡 **Pro Tips**:
- The API key won't be visible as you type
- Use models with 128K+ token context windows for best results
- Request high TPM (1M+ recommended) for smooth performance
- Configuration is stored in `~/.azure/aksAgent.config`

### Alternative Configuration Methods

<details>
<summary><strong>Manual Config File</strong></summary>

Skip interactive setup by creating `~/.azure/aksAgent.config`:

```yaml
model: azure/gpt-4o
api_key: your-api-key-here
azure_api_base: https://your-resource.openai.azure.com/
azure_api_version: 2024-08-01-preview
```
</details>

<details>
<summary><strong>Other LLM Providers</strong></summary>

Supported alternatives:
- **OpenAI** (direct): Use `openai` provider with your OpenAI API key
- **Anthropic** (Claude): Use `anthropic` provider
- **Google Gemini**: Use `gemini` provider  
- **OpenAI-compatible**: Any compatible API endpoint
</details>

---

## Using the Agent

### Basic Usage

Simply ask your question in natural language:

```bash
az aks agent "What's wrong with my cluster?"
```

The agent enters **interactive mode** by default, allowing continuous conversation. Exit anytime with `/exit`.

### Real-World Examples

```bash
# Cluster health check
az aks agent "Are all my nodes healthy?"

# Pod troubleshooting
az aks agent "Why is the payment-service pod restarting?"

# Performance investigation
az aks agent "Which pods are consuming the most memory?"

# Configuration audit
az aks agent "Show me all pods without resource limits"

# Network debugging
az aks agent "Why can't my frontend reach the backend service?"
```

### Command Line Options

| Flag | Purpose | Example |
|------|---------|---------|
| `--model` | Specify which AI model to use | `--model=azure/gpt-4o` |
| `--no-interactive` | Run single query without conversation | Quick scripts and automation |
| `--show-tool-output` | Display raw tool execution details | Deep debugging sessions |
| `--max-steps` | Limit investigation depth | `--max-steps=15` (default: 10) |
| `--config-file` | Use custom configuration | `--config-file=~/my-config.yaml` |
| `--resource-group` | Target specific RG | Required for MCP server mode |
| `--name` | Target specific cluster | Required for MCP server mode |

### Interactive Mode Commands

Inside an interactive session, use these special commands:

```bash
/help      # Display all available commands
/tools     # View active toolsets and their status
/last      # Review outputs from previous analysis
/clear     # Reset conversation and start fresh
/context   # Check token usage and context size
/run       # Execute bash command and share with AI
/shell     # Launch interactive shell session
/feedback  # Submit feedback on responses
/exit      # End session
```

### Model Selection

Different model formats for different providers:

```bash
# Azure OpenAI
az aks agent "question" --model=azure/gpt-4o

# OpenAI direct
az aks agent "question" --model=gpt-4o

# Anthropic Claude
az aks agent "question" --model=anthropic/claude-sonnet-4
```

### Batch Mode (Non-Interactive)

Perfect for scripts, CI/CD pipelines, or quick checks:

```bash
az aks agent "Count pods in production namespace" \
  --model=azure/gpt-4o \
  --no-interactive \
  --show-tool-output
```

---

## Deploy Sample Applications

The `sample-apps/` directory contains Kubernetes applications with intentional issues to demonstrate the Agentic CLI's troubleshooting capabilities.

### Step 1: Deploy Demo Applications

After your AKS cluster is ready:

```bash
cd sample-apps
./deploy-samples.sh
```

This deploys 9 different applications, each with a specific issue:

1. **CrashLoop App** - Missing environment variables causing crashes
2. **OOMKilled App** - Memory limit exceeded
3. **ImagePull Error** - Invalid container image reference
4. **Pending Pod** - Insufficient cluster resources
5. **Liveness Failure** - Health check failures
6. **Network Policy Block** - Service communication blocked
7. **ConfigMap Missing** - Missing configuration dependency
8. **Init Container Failure** - Failed initialization
9. **Resource Issues** - Missing limits and over-provisioning

### Step 2: Verify Deployment

```bash
kubectl get pods -n troubleshooting-demos
```

You should see various pod states (Running, CrashLoopBackOff, Pending, etc.).

### Step 3: Troubleshoot with the Agent

Now investigate issues using natural language:

```bash
# General health check
az aks agent "What issues exist in the troubleshooting-demos namespace?"

# Specific problems
az aks agent "Why is the crashloop-app pod failing?"
az aks agent "Which pods are pending and why?"
az aks agent "Why is oomkilled-app restarting?"
az aks agent "Can frontend-app reach backend-service?"
az aks agent "What's wrong with the init-failure-app?"
```

### Step 4: Cleanup Demo Apps

Remove all sample applications when done:

```bash
cd sample-apps
./cleanup-samples.sh
```

See [sample-apps/README.md](sample-apps/README.md) for detailed information about each application.

---

## Advanced Configuration

### Custom Config Files

Skip the interactive setup by creating a configuration file directly. Store your LLM credentials, preferred models, and custom toolsets.

Default location: `~/.azure/aksAgent.config`

View example configuration:
- [Sample Config on GitHub](https://github.com/Azure/agentic-cli-for-aks/blob/main/exampleconfig.yaml)

Use custom config:

```bash
az aks agent "Query here" --config-file ./custom-config.yaml
```

### Understanding Toolsets

The agent leverages multiple "toolsets"—specialized modules that interact with different data sources:

**Standard Toolsets:**
- `kubernetes/core` - Basic cluster operations
- `kubernetes/logs` - Pod and container logs
- `kubernetes/live-metrics` - Real-time performance data
- `aks/core` - AKS-specific Azure integrations
- `aks/node-health` - Node diagnostics
- `runbook` - Automated troubleshooting procedures
- `bash` - Direct command execution
- `internet` - External documentation and resources

Refresh toolset availability:

```bash
az aks agent "question" --refresh-toolsets
```

### MCP Server Integration

For advanced telemetry and deeper Azure integration, enable the AKS Model Context Protocol (MCP) server:

```bash
az aks agent "diagnose node issues" \
  --model=azure/gpt-4o \
  --aks-mcp \
  --name my-cluster \
  --resource-group my-rg
```

Check MCP server status:

```bash
az aks agent --status
```

⚠️ **Note**: MCP mode requires explicitly specifying cluster name and resource group—it doesn't auto-detect from kubectl context.

---

## Best Practices

### 1. Start Broad, Then Narrow

Begin with general questions, then dive deeper based on initial findings:

```bash
# Start here
"What issues exist in my cluster?"

# Then follow up
"Show me details about the failing pods"

# Finally investigate
"What's causing the OOMKilled errors?"
```

### 2. Provide Context in Questions

More context = better answers:

❌ "Why is it broken?"
✅ "Why is the order-service deployment in crash loop?"

### 3. Use Interactive Mode for Complex Issues

Let the agent build context across multiple queries rather than running isolated commands.

### 4. Review Tool Outputs When Stuck

Enable `--show-tool-output` to see what the agent is actually checking—helps identify missing permissions or data.

### 5. Manage Token Limits

Large clusters generate lots of data. Use `/context` to monitor token usage. Consider targeting specific namespaces in your questions.

---

## Troubleshooting the Agent

### Installation Issues

```bash
# Force reinstall
az extension remove --name aks-agent
az extension add --name aks-agent --debug
```

### Configuration Problems

If `agent-init` fails:
- Verify API keys are correct (no extra spaces)
- Confirm endpoint URLs end with `/` for Azure OpenAI
- Check API version compatibility
- Manually edit config file at `~/.azure/aksAgent.config`

### Permission Errors

Ensure your Azure identity has:
- AKS cluster access (Reader + Azure Kubernetes Service Cluster User Role minimum)
- Kubectl permissions via RBAC
- Subscription-level read access for Azure Resource Manager queries

### Poor Response Quality

- Use newer models (GPT-4o, Claude Sonnet 4)
- Increase TPM quota on Azure OpenAI deployments
- Be more specific in your questions
- Check if toolsets are loading properly with `/tools`

---

## Cleanup

### Remove Demo Applications

```bash
cd sample-apps
./cleanup-samples.sh
```

### Remove Agentic CLI Extension

```bash
az extension remove --name aks-agent --debug
```

### Delete Infrastructure

Remove all deployed Azure resources:

```bash
./cleanup.sh
```

Or manually:

```bash
az group delete --name rg-aksagent-demo --yes --no-wait
```

⚠️ **Warning**: This will permanently delete all resources in the resource group.

---

## Learn More

- **Official Documentation**: [AKS Agentic CLI Overview](https://learn.microsoft.com/en-us/azure/aks/cli-agent-for-aks-overview)
- **Troubleshooting Guide**: [Common Issues and Solutions](https://learn.microsoft.com/en-us/azure/aks/cli-agent-for-aks-troubleshoot)
- **FAQ**: [Frequently Asked Questions](https://learn.microsoft.com/en-us/azure/aks/cli-agent-for-aks-faq)
- **GitHub Repository**: [agentic-cli-for-aks](https://github.com/Azure/agentic-cli-for-aks)
- **AKS MCP Server**: [Model Context Protocol Integration](https://github.com/Azure/aks-mcp)

## Contributing

Found an issue? Have a feature idea? The agent is actively developed and welcomes community input.

---

**Status**: Preview | **Last Updated**: December 2025
