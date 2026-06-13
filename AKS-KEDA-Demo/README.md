# AKS KEDA Demo

A hands-on demo showing how **KEDA (Kubernetes Event-Driven Autoscaling)** works on
**Azure Kubernetes Service** using the managed KEDA add-on.

Infrastructure in this folder is provisioned with **Terraform modules**.

## Terraform Module Layout

```text
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── terraform.tfvars.example
└── modules/
  ├── acr/
  ├── aks/
  ├── log_analytics/
  ├── monitoring/
  ├── eventhub/
  └── storage/
```

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
│  Event Hub         │───▶│  ScalerFactory  │───▶│  Deployment replica   │
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
└── Azure Event Hub Namespace + Hub    ← Scenario 05 trigger source
```

## Scenarios

| # | Scenario | Trigger | Use Case |
|---|---|---|---|
| 01 | [Azure Storage Queue](scenarios/01-storage-queue/) | `azure-queue` | Background job workers, async processing |
| 02 | [Cron (time-based)](scenarios/02-cron/) | `cron` | Business hours scaling, batch windows |
| 03 | [Prometheus](scenarios/03-prometheus/) | `prometheus` | HTTP RPS, custom app metrics, SLO-based scaling |
| 04 | [CPU / Memory](scenarios/04-cpu-memory/) | `cpu` + `memory` | Traditional resource-based scaling with KEDA features |
| 05 | [Azure Event Hub](scenarios/05-eventhub/) | `azure-event-hubs` | Stream processing, IoT telemetry, high-throughput events |

## Prerequisites

| Tool | Purpose |
|---|---|
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | Deploy infrastructure |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Manage Kubernetes resources |
| [Docker](https://docs.docker.com/get-docker/) | Build and run sample apps locally (optional) |

## Quick Start

```bash
# 1. Clone and navigate to the demo folder
cd AKS-KEDA-Demo

# 2. Make scripts executable
chmod +x deploy.sh cleanup.sh

# 3. Login to Azure
az login

# 4. (Optional) Customize Terraform inputs
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 5. Deploy the AKS cluster + supporting resources (~10 minutes)
./deploy.sh

# 6. Verify KEDA is running
kubectl get pods -n kube-system | grep keda

# Expected output:
# keda-operator-xxxxx             1/1   Running
# keda-operator-metrics-apiserver 1/1   Running
# keda-admission-xxxxx            1/1   Running
```

## ACR Provisioning and AKS Connection

This demo now provisions Azure Container Registry (ACR) through Terraform and
connects AKS by granting the cluster kubelet identity the `AcrPull` role on that ACR.

Configure this in [terraform/terraform.tfvars](terraform/terraform.tfvars):

```hcl
acr_name = "acrkedademoneu001"
acr_sku  = "Basic"
```

After deployment, `deploy.sh` prints:
- ACR name
- ACR login server

Use that login server to push and reference your demo images.

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

## Sample Apps

The `sample-apps/` directory contains production-quality Python consumer applications
for local testing with Docker Compose before deploying to AKS.

```
sample-apps/
├── storage-queue-consumer/   Python app for Scenario 01 (Azure Storage Queue)
│   ├── app.py                Polls queue, dequeues and deletes messages
│   ├── requirements.txt
│   └── Dockerfile            Multi-stage build, non-root user
├── eventhub-consumer/        Python app for Scenario 05 (Azure Event Hub)
│   ├── app.py                Event Processor with optional Blob checkpoint store
│   ├── requirements.txt
│   └── Dockerfile
├── docker-compose.yml        Runs both consumers together
└── .env.example              Environment variable template — copy to .env
```

### Run locally

```bash
cd sample-apps
cp .env.example .env
# Edit .env with your Azure connection strings

# Build and start both consumers
docker compose up --build

# Or start only one
docker compose up --build storage-queue-consumer
docker compose up --build eventhub-consumer
```

### Build and push to ACR (for Kubernetes deployment)

```bash
ACR=<your-acr-name>
az acr login --name $ACR

# Storage Queue Consumer
docker build -t $ACR.azurecr.io/storage-queue-consumer:latest \
  sample-apps/storage-queue-consumer/
docker push $ACR.azurecr.io/storage-queue-consumer:latest

# Event Hub Consumer
docker build -t $ACR.azurecr.io/eventhub-consumer:latest \
  sample-apps/eventhub-consumer/
docker push $ACR.azurecr.io/eventhub-consumer:latest
```

Then update the `image:` field in
`scenarios/01-storage-queue/01-deployment.yaml` and
`scenarios/05-eventhub/01-deployment.yaml` with your ACR image paths.

## KEDA Add-on vs Self-Managed KEDA

| | AKS KEDA Add-on | Helm-installed KEDA |
|---|---|---|
| Installation | Enabled via Terraform/CLI | `helm install kedacore/keda` |
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
