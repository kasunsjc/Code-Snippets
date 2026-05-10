# Scenario 01 — Azure Storage Queue Scaler

## Concept

KEDA watches the message count in an **Azure Storage Queue**. When messages queue up,
it scales the consumer `Deployment` out (more pods). When the queue drains, it scales back in —
all the way to **zero** (scale-to-zero), which saves resources when there is no work.

```
Producer Job  ──▶  Azure Storage Queue  ──▶  KEDA ScaledObject  ──▶  Consumer Deployment
(pushes 100 msgs)   (message count monitored)    (0→N replicas)         (dequeues & processes)
```

## Key KEDA Resources

| Resource | Purpose |
|---|---|
| `TriggerAuthentication` | Stores the Storage connection string from a K8s Secret |
| `ScaledObject` | Maps the queue length to replica count |

## Files

| File | Description |
|---|---|
| `00-secret.yaml` | **Template only** — `deploy.sh` creates the real secret |
| `01-deployment.yaml` | Consumer `Deployment` (starts at 0 replicas) |
| `02-trigger-auth.yaml` | `TriggerAuthentication` referencing the K8s Secret |
| `03-scaled-object.yaml` | `ScaledObject` — scale when queue length > 5 messages/replica |
| `04-producer-job.yaml` | `Job` that pushes 100 messages (triggers scale-out) |

## Steps

```bash
# 1. Deploy consumer, TriggerAuthentication and ScaledObject
kubectl apply -f scenarios/01-storage-queue/ -n keda-demo

# 2. Verify 0 replicas (queue is empty — scaled to zero)
kubectl get deployment queue-consumer -n keda-demo

# 3. Watch pods in a second terminal
kubectl get pods -n keda-demo -w

# 4. Send 100 messages — triggers scale-out
kubectl apply -f scenarios/01-storage-queue/04-producer-job.yaml -n keda-demo

# 5. Watch KEDA scale the consumer (should reach ~10 replicas then drain back to 0)
kubectl get scaledobject storage-queue-scaler -n keda-demo
kubectl describe hpa keda-hpa-storage-queue-scaler -n keda-demo

# 6. Cleanup
kubectl delete -f scenarios/01-storage-queue/ -n keda-demo
```

## Scale Logic

- `queueLength: "5"` — target 1 replica per 5 messages in the queue
- `minReplicaCount: 0` — scale to zero when the queue is empty
- `maxReplicaCount: 10` — cap at 10 replicas

With 100 messages queued, KEDA will scale towards 20 replicas but is capped at 10.
As each pod dequeues messages, the count drops and pods are terminated.
