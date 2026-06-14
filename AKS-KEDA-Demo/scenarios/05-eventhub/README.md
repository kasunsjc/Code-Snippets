# Scenario 05 — Azure Event Hub Scaler

## Concept

KEDA monitors the **unprocessed event lag** for a consumer group in Azure Event Hub.
When events accumulate (because they arrive faster than the consumer processes them),
KEDA scales the consumer `Deployment` out. When the consumer catches up, KEDA scales
back in — including to **zero** when there is no lag.

```
Producer Deployment  ──▶  Azure Event Hub  ──▶  KEDA reads checkpoint lag
(continuous load)       (partitioned log)           │
                                     ScaledObject adjusts replicas
                                               │
                                     eventhub-consumer Deployment
                                     (reads from Blob checkpoint store)
```

## How KEDA measures lag

KEDA compares two values per partition:
- **Latest sequence number** — the most recently written event
- **Checkpoint offset** — the last event the consumer confirmed (stored in Blob Storage)

The difference (lag) across all partitions is divided by `unprocessedEventThreshold`
to determine the desired replica count.

This is why the consumer app **must** write Blob Storage checkpoints and both KEDA and
the consumer must point at the **same** storage container.

## Files

| File | Description |
|---|---|
| `00-secret.yaml` | Template — `deploy.sh` creates the real Secret |
| `01-deployment.yaml` | Consumer Deployment (starts at 0 replicas) |
| `02-trigger-auth.yaml` | `TriggerAuthentication` — Event Hub + Storage connection strings |
| `03-scaled-object.yaml` | `ScaledObject` — scale when unprocessed events > 10/replica |
| `05-producer-deployment.yaml` | Continuous producer Deployment to generate load |

## Prerequisites

### 1. Create the Event Hub namespace and hub

The Terraform stack in this demo does not create an Event Hub namespace.
Create one manually before running this scenario:

```bash
# Create Event Hub namespace
az eventhubs namespace create \
  --resource-group rg-aks-keda-demo \
  --name <namespace-name> \
  --location northeurope \
  --sku Standard

# Create the Event Hub (topic) with 4 partitions
az eventhubs eventhub create \
  --resource-group rg-aks-keda-demo \
  --namespace-name <namespace-name> \
  --name keda-demo-hub \
  --partition-count 4 \
  --message-retention 1
```

### 2. Create the checkpoint container

```bash
az storage container create \
  --name eventhub-checkpoints \
  --account-name <storage-account-name> \
  --auth-mode login
```

### 3. Build and push the consumer image

```bash
# Build
docker build -t <YOUR_ACR>.azurecr.io/eventhub-consumer:latest \
  sample-apps/eventhub-consumer/

# Push
az acr login --name <YOUR_ACR>
docker push <YOUR_ACR>.azurecr.io/eventhub-consumer:latest
```

Then update the `image:` field in `01-deployment.yaml`.

### 4. Create the Kubernetes Secret

```bash
EH_CS=$(az eventhubs namespace authorization-rule keys list \
  --resource-group rg-aks-keda-demo \
  --namespace-name <namespace-name> \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv)

ST_CS=$(az storage account show-connection-string \
  --name <storage-account-name> \
  --resource-group rg-aks-keda-demo \
  --query connectionString -o tsv)

kubectl create secret generic azure-eventhub-secret \
  --namespace keda-demo \
  --from-literal=eventhub-connection-string="$EH_CS" \
  --from-literal=storage-connection-string="$ST_CS" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Steps

```bash
# 1. Apply the consumer Deployment, TriggerAuthentication and ScaledObject
kubectl apply -f scenarios/05-eventhub/01-deployment.yaml -n keda-demo
kubectl apply -f scenarios/05-eventhub/02-trigger-auth.yaml -n keda-demo
kubectl apply -f scenarios/05-eventhub/03-scaled-object.yaml -n keda-demo

# 2. Verify 0 replicas (no lag — scaled to zero)
kubectl get deployment eventhub-consumer -n keda-demo

# 3. Check ScaledObject is ready
kubectl get scaledobject eventhub-scaler -n keda-demo

# 4. Watch pods in a second terminal
kubectl get pods -n keda-demo -w

# 5. Start producer — generates events continuously and triggers scale-out
kubectl apply -f scenarios/05-eventhub/05-producer-deployment.yaml -n keda-demo

# 6. Watch KEDA scale the consumer out (up to 10 replicas)
kubectl describe scaledobject eventhub-scaler -n keda-demo
kubectl get hpa -n keda-demo

# 7. After events are processed, watch replicas scale back to zero
kubectl get deployment eventhub-consumer -n keda-demo -w

# Optional: stop producer to let consumers fully drain backlog
kubectl delete deployment eventhub-producer -n keda-demo

# 8. Cleanup
kubectl delete -f scenarios/05-eventhub/ -n keda-demo
```

## Local Testing with Docker Compose

Before deploying to Kubernetes, test the consumer app locally:

```bash
cd sample-apps
cp .env.example .env
# Edit .env with your Event Hub and Storage connection strings

docker compose up --build eventhub-consumer
```

In a separate terminal, send test events using the Azure CLI or SDK.

## Scale Logic

| Unprocessed events | Replicas |
|---|---|
| 0 | 0 (scale-to-zero) |
| 1–10 | 1 |
| 11–20 | 2 |
| 91–100 | 10 (capped) |

Threshold is configured via `unprocessedEventThreshold: "10"` in `03-scaled-object.yaml`.
