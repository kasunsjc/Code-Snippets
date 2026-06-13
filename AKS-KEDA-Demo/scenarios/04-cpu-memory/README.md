# Scenario 04 — CPU & Memory Scaler

## Concept

KEDA's **cpu** and **memory** scalers bridge KEDA and the built-in Kubernetes
metrics server. They behave like a Horizontal Pod Autoscaler (HPA) with CPU/memory
triggers, but you get all the KEDA features on top (scale-to-zero, multiple trigger
support, unified management).

> **Key point**: Unlike HPA which only supports CPU/memory, KEDA allows you to
> **combine** CPU/memory triggers with queue, cron, or Prometheus triggers in a
> **single ScaledObject** — enabling sophisticated multi-signal autoscaling.

```
High CPU load  ──▶  Metrics Server  ──▶  KEDA ScaledObject (cpu trigger)
                                          + azure-queue trigger
                                          + cron trigger
                                          ──▶  scales on the HIGHEST demand signal
```

## Files

| File | Description |
|---|---|
| `01-deployment.yaml` | CPU-intensive app Deployment |
| `02-scaled-object.yaml` | ScaledObject with both CPU and memory triggers |
| `03-cpu-stress-job.yaml` | Job that stresses CPU to trigger scale-out |

## Requirements

The **Kubernetes Metrics Server** must be installed (it is included by default on AKS):
```bash
kubectl top nodes   # verify metrics-server is working
kubectl top pods -n keda-demo
```

## Steps

```bash
# 1. Deploy the app and ScaledObject
kubectl apply -f scenarios/04-cpu-memory/ -n keda-demo

# 2. Check baseline replica count
kubectl get deployment cpu-app -n keda-demo

# 3. Watch CPU metrics
kubectl top pods -n keda-demo

# 4. Run CPU stress test to trigger scale-out
kubectl apply -f scenarios/04-cpu-memory/03-cpu-stress-job.yaml -n keda-demo

# 5. Watch replicas increase as CPU utilisation climbs above 50%
kubectl get deployment cpu-app -n keda-demo -w

# 6. After stress job completes, replicas scale back down
kubectl get pods -n keda-demo -w

# 7. Cleanup
kubectl delete -f scenarios/04-cpu-memory/ -n keda-demo
```

## Scale Logic

- CPU trigger: `value: "50"` with `metricType: Utilization` — add a replica when average
  CPU utilization across all pods exceeds 50%
- Memory trigger: `value: "70"` — add a replica when average memory utilization exceeds 70%
- KEDA takes the **maximum** of all trigger recommendations (most demanding wins)
