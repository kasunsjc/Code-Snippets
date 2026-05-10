# Scenario 03 — Cron (Time-Based) Scaler

## Concept

The **cron** scaler scales a Deployment on a fixed schedule — no external queue or metric
needed. It is ideal for workloads with predictable load patterns (business hours,
batch windows, end-of-day reporting).

```
Monday–Friday 08:00 AEDT  ──▶  KEDA sets replicas = 5   (business hours)
Monday–Friday 18:00 AEDT  ──▶  KEDA sets replicas = 1   (off-hours minimum)
```

## How Cron Scaler Works

KEDA uses two cron expressions:
- **`start`** — when to enter the "active" window (replicas → `desiredReplicas`)
- **`end`**   — when to exit the "active" window (replicas → `minReplicaCount`)

Between `start` and `end` you get `desiredReplicas`.  
Outside that window you get `minReplicaCount` (can be 0 for scale-to-zero).

> **Multiple windows**: stack multiple cron triggers on the same ScaledObject to model
> peak/off-peak/batch windows simultaneously.

## Files

| File | Description |
|---|---|
| `01-deployment.yaml` | Sample app Deployment |
| `02-scaled-object.yaml` | ScaledObject with cron trigger (no TriggerAuthentication needed) |

## Steps

```bash
# 1. Deploy the app and the ScaledObject
kubectl apply -f scenarios/03-cron/ -n keda-demo

# 2. Check the current replica count (depends on current time)
kubectl get deployment cron-app -n keda-demo

# 3. Inspect the ScaledObject
kubectl describe scaledobject cron-scaler -n keda-demo

# 4. Manually patch to simulate time change (for demo)
#    Temporarily change the cron to 1 minute from now:
kubectl edit scaledobject cron-scaler -n keda-demo

# 5. Watch replicas change
kubectl get deployment cron-app -n keda-demo -w

# 6. Cleanup
kubectl delete -f scenarios/03-cron/ -n keda-demo
```

## Timezone Note

Cron expressions use the timezone specified in `timezone`. This demo uses `Australia/Melbourne`.
Change it to match your local timezone: `America/New_York`, `Europe/London`, `Asia/Singapore`, etc.

See the full list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
