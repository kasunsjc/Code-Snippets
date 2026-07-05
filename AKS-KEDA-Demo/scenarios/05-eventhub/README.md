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
| `01-deployment.yaml` | Consumer Deployment (starts at 0 replicas, includes liveness probe) |
| `02-trigger-auth.yaml` | `TriggerAuthentication` — Event Hub + Storage connection strings |
| `03-scaled-object.yaml` | `ScaledObject` — scale when unprocessed events > 10/replica |
| `05-producer-deployment.yaml` | Continuous producer Deployment to generate load (includes liveness probe) |

## Health Checks

Both the consumer and producer Deployments include an exec-based **liveness probe**
that verifies the Python process is running:

```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - "cat /proc/1/cmdline | grep -q app.py"   # consumer
  initialDelaySeconds: 30
  periodSeconds: 60
  failureThreshold: 3
```

Kubernetes will restart the container if the process exits unexpectedly (e.g., a
fatal Azure SDK error). The `initialDelaySeconds: 30` allows time for the Event Hub
connection to be established before the first probe fires.

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

## Optional Manual Deployment Path

Use this section only when you are not using `./deploy.sh --demo eventhub --image-tag <tag>`.

### 1. Event Hub namespace/hub and checkpoint container are provisioned by Terraform

When you run `./deploy.sh` (or `terraform apply`), this demo now provisions:
1. Event Hub namespace
2. Event Hub `keda-demo-hub`
3. Storage checkpoint container (default: `eventhub-checkpoints`)

You can verify the resolved names from Terraform outputs:

```bash
terraform -chdir=terraform output eventhub_namespace_name
terraform -chdir=terraform output eventhub_name
terraform -chdir=terraform output storage_account_name
terraform -chdir=terraform output checkpoint_container_name
```

Only create these manually if you are intentionally bypassing Terraform and using existing Azure resources.

### 2. Build and push consumer and producer images

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
CHECKPOINT_CONTAINER_NAME=$(terraform -chdir=terraform output -raw checkpoint_container_name)

for f in 01-deployment.yaml 02-trigger-auth.yaml 03-scaled-object.yaml 05-producer-deployment.yaml; do
  sed -e "s|{{ ACR_LOGIN_SERVER }}|$ACR_LOGIN_SERVER|g" \
      -e "s|{{ CHECKPOINT_CONTAINER_NAME }}|$CHECKPOINT_CONTAINER_NAME|g" \
      -e "s|{{ IMAGE_TAG }}|$IMAGE_TAG|g" \
      "scenarios/05-eventhub/$f" | kubectl apply -n keda-demo -f -
done
```

### 3. Create the Kubernetes Secret

Use names from Terraform outputs to avoid mismatches:

```bash
EH_NAMESPACE=$(terraform -chdir=terraform output -raw eventhub_namespace_name)
STORAGE_ACCOUNT=$(terraform -chdir=terraform output -raw storage_account_name)
```

```bash
EH_CS=$(az eventhubs namespace authorization-rule keys list \
  --resource-group rg-aks-keda-demo \
  --namespace-name "$EH_NAMESPACE" \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv)

ST_CS=$(az storage account show-connection-string \
  --name "$STORAGE_ACCOUNT" \
  --resource-group rg-aks-keda-demo \
  --query connectionString -o tsv)

kubectl create secret generic azure-eventhub-secret \
  --namespace keda-demo \
  --from-literal=eventhub-connection-string="$EH_CS" \
  --from-literal=storage-connection-string="$ST_CS" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## How to Test Scale-Up and Scale-Down

### 1) Deploy the scenario

```bash
./deploy.sh --demo eventhub --image-tag latest
```

### 2) Verify scaler is ready

```bash
kubectl get scaledobject eventhub-scaler -n keda-demo
kubectl describe scaledobject eventhub-scaler -n keda-demo
```

Expected: `READY=True`

### 3) Scale-up test (generate backlog)

The producer Deployment is already continuous, but you can increase pressure to make scale-up obvious:

```bash
# Optional: increase producer rate
kubectl set env deployment/eventhub-producer -n keda-demo EVENT_INTERVAL_SECONDS=0.05 BATCH_SIZE=20

# Watch consumer replicas and HPA in separate terminals
kubectl get deployment eventhub-consumer -n keda-demo -w
kubectl get hpa keda-hpa-eventhub-scaler -n keda-demo -w
kubectl get scaledobject eventhub-scaler -n keda-demo -w
```

Expected:
- `eventhub-consumer` scales above 0
- HPA target/metrics increase and desired replicas grow
- ScaledObject shows `ACTIVE=True`

### 4) Scale-down test (drain backlog)

```bash
# Stop producing new events
kubectl scale deployment eventhub-producer -n keda-demo --replicas=0

# Keep watching until lag is drained and cooldown expires
kubectl get deployment eventhub-consumer -n keda-demo -w
kubectl get hpa keda-hpa-eventhub-scaler -n keda-demo -w
```

Expected:
- Consumer replicas gradually decrease
- Eventually returns to `0` replicas (`minReplicaCount: 0`)

If downscale is slow, remember this scenario uses:
- `pollingInterval: 15`
- `cooldownPeriod: 60`

So a few minutes is normal after traffic stops.

### 5) Optional reset for repeatable tests

```bash
# Restore default producer rate and restart producer
kubectl set env deployment/eventhub-producer -n keda-demo EVENT_INTERVAL_SECONDS=5 BATCH_SIZE=10
kubectl scale deployment eventhub-producer -n keda-demo --replicas=1
```

### 6) Cleanup

```bash
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

4. Confirm `azure-storage-blob` exists in the consumer image (required by checkpoint store):

```bash
POD=$(kubectl get pods -n keda-demo -l app=eventhub-consumer -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n keda-demo "$POD" -- python -c "import importlib.util; print('azure-storage-blob', 'OK' if importlib.util.find_spec('azure.storage.blob') else 'MISSING')"
```

If this prints `MISSING`, rebuild and redeploy the eventhub-consumer image:

```bash
./deploy.sh --demo eventhub --image-tag v1
```
