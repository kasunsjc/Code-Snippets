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
the consumer must point at the **same** storage container and consumer group (`$Default` in this demo).

## Files

| File | Description |
|---|---|
| `00-secret.yaml` | Template — `deploy.sh` creates the real Secret |
| `01-deployment.yaml` | Consumer Deployment (starts at 0 replicas) |
| `02-trigger-auth.yaml` | `TriggerAuthentication` — Event Hub + Storage connection strings |
| `03-scaled-object.yaml` | `ScaledObject` — scale when unprocessed events > 10/replica |
| `05-producer-deployment.yaml` | Continuous producer Deployment to generate load |

## Recommended Deployment Path

Use the repo-level deployment script so templated image references are substituted correctly.

```bash
./deploy.sh --demo eventhub --image-tag latest
```

This workflow:
1. Builds amd64 images for producer and consumer.
2. Pushes images to ACR.
3. Substitutes `{{ ACR_LOGIN_SERVER }}` and `{{ IMAGE_TAG }}`.
4. Applies Event Hub manifests and secrets.

## Prerequisites (Manual Path)

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

### 3. Build and push consumer and producer images

```bash
# Build consumer
docker build -t <YOUR_ACR>.azurecr.io/eventhub-consumer:latest \
  sample-apps/eventhub-consumer/

# Build producer
docker build -t <YOUR_ACR>.azurecr.io/eventhub-producer:latest \
  sample-apps/eventhub-producer/

# Push
az acr login --name <YOUR_ACR>
docker push <YOUR_ACR>.azurecr.io/eventhub-consumer:latest
docker push <YOUR_ACR>.azurecr.io/eventhub-producer:latest
```

Do not apply templated manifests directly. Render them with substitution:

```bash
ACR_LOGIN_SERVER=<YOUR_ACR>.azurecr.io
IMAGE_TAG=latest

for f in 01-deployment.yaml 02-trigger-auth.yaml 03-scaled-object.yaml 05-producer-deployment.yaml; do
  sed -e "s|{{ ACR_LOGIN_SERVER }}|$ACR_LOGIN_SERVER|g" \
      -e "s|{{ IMAGE_TAG }}|$IMAGE_TAG|g" \
      "scenarios/05-eventhub/$f" | kubectl apply -n keda-demo -f -
done
```

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

## Validation Steps

```bash
# 1. Ensure resources are deployed (recommended via deploy.sh)
./deploy.sh --demo eventhub --image-tag latest

# 2. Verify 0 replicas (no lag — scaled to zero)
kubectl get deployment eventhub-consumer -n keda-demo

# 3. Check ScaledObject is ready
kubectl get scaledobject eventhub-scaler -n keda-demo

# 4. Watch pods in a second terminal
kubectl get pods -n keda-demo -w

# 5. Producer runs continuously and drives scale-out
kubectl get deployment eventhub-producer -n keda-demo

# 6. Watch KEDA scale the consumer out (up to 10 replicas)
kubectl describe scaledobject eventhub-scaler -n keda-demo
kubectl get hpa -n keda-demo

# 7. After events are processed, watch replicas scale back to zero
kubectl get deployment eventhub-consumer -n keda-demo -w

# Optional: stop producer to let consumers fully drain backlog
kubectl scale deployment eventhub-producer -n keda-demo --replicas=0

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

## Troubleshooting

If replicas do not scale down after stopping producer:
1. Confirm scaler metric value reaches 0:

```bash
kubectl get --raw '/apis/external.metrics.k8s.io/v1beta1/namespaces/keda-demo/s0-azure-eventhub-$Default?labelSelector=scaledobject.keda.sh%2Fname%3Deventhub-scaler'
```

2. Confirm consumer is not in in-memory checkpoint mode:

```bash
kubectl logs deployment/eventhub-consumer -n keda-demo --tail=200 | grep -Ei 'checkpoint|in-memory'
```

3. Confirm checkpoint import in the running pod:

```bash
POD=$(kubectl get pods -n keda-demo -l app=eventhub-consumer -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n keda-demo "$POD" -- python -c "from azure.eventhub.extensions.checkpointstoreblob import BlobCheckpointStore; print('checkpoint-import-ok')"
```
