# Scenario 02 — Azure Service Bus Queue Scaler

## Concept

Same pattern as Scenario 01, but using **Azure Service Bus** — a fully managed enterprise
message broker that supports ordering, dead-lettering, sessions, and transactions.

```
Producer Job  ──▶  Service Bus Queue  ──▶  KEDA ScaledObject  ──▶  Consumer Deployment
(pushes 100 msgs)   (active messages monitored)  (0→N replicas)     (receives & completes)
```

KEDA monitors the **active message count** (messages waiting to be consumed).
Locked (in-flight) messages are not counted, which prevents over-scaling.

## Key Difference vs Storage Queue

| Feature | Storage Queue | Service Bus |
|---|---|---|
| Message ordering | No guarantee | Optional FIFO with sessions |
| Dead-lettering | No | Yes (built-in DLQ) |
| Message lock | No | Yes (prevents duplicate processing) |
| Max message size | 64 KB | 256 KB (Standard) |
| KEDA trigger type | `azure-queue` | `azure-servicebus` |
| Auth parameter | `connection` | `connection` |
| Scale metric | Queue length | Active message count |

## Files

| File | Description |
|---|---|
| `00-secret.yaml` | **Template only** — `deploy.sh` creates the real secret |
| `01-deployment.yaml` | Consumer `Deployment` (starts at 0 replicas) |
| `02-trigger-auth.yaml` | `TriggerAuthentication` for Service Bus |
| `03-scaled-object.yaml` | `ScaledObject` — scale when active messages > 5/replica |
| `04-producer-job.yaml` | `Job` that sends 100 messages (triggers scale-out) |

## Steps

```bash
# 1. Deploy consumer, TriggerAuthentication and ScaledObject
kubectl apply -f scenarios/02-service-bus/ -n keda-demo

# 2. Verify 0 replicas (no messages — scaled to zero)
kubectl get deployment servicebus-consumer -n keda-demo

# 3. Watch pods in a second terminal
kubectl get pods -n keda-demo -w

# 4. Send 100 messages to the Service Bus queue
kubectl apply -f scenarios/02-service-bus/04-producer-job.yaml -n keda-demo

# 5. Observe KEDA scaling up
kubectl get scaledobject servicebus-scaler -n keda-demo

# 6. Inspect the HPA KEDA created automatically
kubectl describe hpa keda-hpa-servicebus-scaler -n keda-demo

# 7. Cleanup
kubectl delete -f scenarios/02-service-bus/ -n keda-demo
```

## Scale Logic

- `messageCount: "5"` — target 1 replica per 5 active messages
- `minReplicaCount: 0` — scale to zero when queue is empty
- `maxReplicaCount: 10` — cap at 10 consumers
