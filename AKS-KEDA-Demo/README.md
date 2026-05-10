# AKS KEDA Demo

A hands-on demo showing how **KEDA (Kubernetes Event-Driven Autoscaling)** works on
**Azure Kubernetes Service** using the managed KEDA add-on.

## What is KEDA?

KEDA extends Kubernetes with **event-driven scaling**. While the built-in Horizontal
Pod Autoscaler (HPA) can only scale on CPU and memory, KEDA can scale on any metric:
queue depth, message count, HTTP requests, cron schedules, database queries, and more.

KEDA works by:
1. Creating a **`ScaledObject`** that maps a trigger to a target Deployment.
2. Translating the trigger into a standard Kubernetes HPA behind the scenes.
3. Polling the trigger source (queue, Prometheus, etc.) on a configurable interval.
4. Including **scale-to-zero** support — pods are removed entirely when there is no work.

```
External Trigger Source           KEDA                    Kubernetes
┌────────────────────┐    ┌─────────────────┐    ┌───────────────────────┐
│  Azure Queue       │    │  ScaledObject   │    │  HPA (auto-created)   │
│  Service Bus       │───▶│  ScalerFactory  │───▶│  Deployment replica   │
│  Prometheus        │    │  Metrics API    │    │  count adjustment     │
│  Cron schedule     │    └─────────────────┘    └───────────────────────┘
└────────────────────┘
```

## Architecture

```
Azure
├── AKS Cluster (KEDA add-on enabled)
│   ├── kube-system
│   │   ├── keda-operator              ← polls trigger sources
│   │   ├── keda-operator-metrics-apiserver  ← serves custom metrics to HPA
│   │   └── keda-admission             ← validates ScaledObject resources
│   └── keda-demo (namespace)
│       ├── Scenarios 01-05 workloads
│       └── K8s Secrets (connection strings)
├── Azure Storage Account + Queue      ← Scenario 01 trigger source
└── Azure Service Bus Namespace + Queue ← Scenario 02 trigger source
```

## Scenarios

| # | Scenario | Trigger | Use Case |
|---|---|---|---|
| 01 | [Azure Storage Queue](scenarios/01-storage-queue/) | `azure-queue` | Background job workers, async processing |
| 02 | [Azure Service Bus](scenarios/02-service-bus/) | `azure-servicebus` | Enterprise messaging, ordered processing |
| 03 | [Cron (time-based)](scenarios/03-cron/) | `cron` | Business hours scaling, batch windows |
| 04 | [Prometheus](scenarios/04-prometheus/) | `prometheus` | HTTP RPS, custom app metrics, SLO-based scaling |
| 05 | [CPU / Memory](scenarios/05-cpu-memory/) | `cpu` + `memory` | Traditional resource-based scaling with KEDA features |

## Prerequisites

| Tool | Purpose |
|---|---|
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | Deploy infrastructure |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Manage Kubernetes resources |
| [Helm](https://helm.sh/docs/intro/install/) | Install Prometheus (Scenario 04 only) |

## Quick Start

```bash
# 1. Clone and navigate to the demo folder
cd AKS-KEDA-Demo

# 2. Make scripts executable
chmod +x deploy.sh cleanup.sh

# 3. Login to Azure
az login

# 4. Deploy the AKS cluster + supporting resources (~10 minutes)
./deploy.sh

# 5. Verify KEDA is running
kubectl get pods -n kube-system | grep keda

# Expected output:
# keda-operator-xxxxx             1/1   Running
# keda-operator-metrics-apiserver 1/1   Running
# keda-admission-xxxxx            1/1   Running
```

## Running a Scenario

Each scenario has its own `README.md` with detailed steps.
The general pattern is the same for all scenarios:

```bash
NAMESPACE="keda-demo"

# Deploy the workload and ScaledObject
kubectl apply -f scenarios/<number>-<name>/ -n $NAMESPACE

# Watch pods
kubectl get pods -n $NAMESPACE -w

# Check ScaledObject status
kubectl get scaledobject -n $NAMESPACE

# Trigger scaling (queue-based scenarios)
kubectl apply -f scenarios/<number>-<name>/04-producer-job.yaml -n $NAMESPACE

# Inspect the underlying HPA that KEDA manages
kubectl get hpa -n $NAMESPACE
kubectl describe hpa keda-hpa-<scaledobject-name> -n $NAMESPACE
```

## Key KEDA Resources

### ScaledObject
The main KEDA resource. Connects a `Deployment` to one or more triggers.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: my-scaler
spec:
  scaleTargetRef:
    name: my-deployment     # Deployment to scale
  minReplicaCount: 0        # 0 = scale-to-zero
  maxReplicaCount: 10
  pollingInterval: 15       # seconds between trigger polls
  cooldownPeriod: 60        # seconds before scaling down
  triggers:
    - type: azure-queue
      metadata:
        queueName: my-queue
        queueLength: "5"
      authenticationRef:
        name: my-trigger-auth
```

### TriggerAuthentication
Provides credentials to KEDA for accessing the trigger source.
Separates authentication from the ScaledObject (reusable, auditable).

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: my-trigger-auth
spec:
  secretTargetRef:
    - parameter: connection    # Parameter name the trigger expects
      name: my-k8s-secret      # K8s Secret name
      key: connection-string   # Key in the Secret
```

### ScaledJob (not covered here)
Like ScaledObject but for `Job`-based workloads — creates new Job instances
instead of scaling a Deployment. Useful for parallel batch processing.

## KEDA Add-on vs Self-Managed KEDA

| | AKS KEDA Add-on | Helm-installed KEDA |
|---|---|---|
| Installation | Enabled via Bicep/CLI | `helm install kedacore/keda` |
| Upgrades | Managed by AKS | Manual |
| Integration | Azure Monitor logs | Configurable |
| Support | Microsoft support | Community |

The AKS add-on is recommended for production workloads.

## Cleanup

```bash
./cleanup.sh
```

## References

- [KEDA Documentation](https://keda.sh/docs/)
- [AKS KEDA Add-on](https://learn.microsoft.com/en-us/azure/aks/keda-about)
- [KEDA Scalers Catalogue](https://keda.sh/docs/scalers/)
- [TriggerAuthentication Reference](https://keda.sh/docs/concepts/authentication/)
