# Demo 03 — Resource Limits & Isolation

In this demo you will learn how to **constrain** the resources that a vcluster and its workloads can consume on the host cluster. This is essential for platform engineers running shared clusters — you need to ensure one tenant cannot starve another.

## Learning Objectives

- Apply Kubernetes `ResourceQuota` and `LimitRange` to a vcluster's host namespace
- Configure the vcluster control plane with its own CPU/memory limits
- Observe what happens when a tenant tries to exceed their quota
- Understand the two layers of resource governance: host namespace and vcluster workloads

## Concepts Explained

### Two Layers of Resource Control

```
┌──────────────────────────────────────────────────────────┐
│  Host AKS Cluster                                        │
│                                                          │
│  Layer 1 (Platform enforced):                            │
│  Namespace "vc-limits" has a ResourceQuota               │
│    → Total CPU: 4 cores, Memory: 4Gi                     │
│    → Max pods: 20                                        │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │  vcluster "limits" (runs inside vc-limits)       │    │
│  │                                                  │    │
│  │  Layer 2 (Tenant enforced via vcluster):         │    │
│  │  vcluster syncs LimitRange/ResourceQuota to      │    │
│  │  host — workloads must have resource requests    │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

### Why Both Layers?

| Layer | Enforced by | Controls |
|---|---|---|
| Host namespace ResourceQuota | Platform engineer | Max resources the entire vcluster can consume |
| vcluster LimitRange | Tenant (optional) | Default/max resources per Pod inside vcluster |

## Files

| File | Purpose |
|---|---|
| [vcluster-with-limits.yaml](vcluster-with-limits.yaml) | vcluster config with resource limits on the control plane |
| [host-namespace-quota.yaml](host-namespace-quota.yaml) | ResourceQuota & LimitRange applied on the HOST namespace |
| [workload-test.yaml](workload-test.yaml) | Test workloads to observe quota enforcement |
| [setup-limits.sh](setup-limits.sh) | Full automated walkthrough script |

## Step-by-Step Walkthrough

### 1. Create the vcluster namespace and apply host-level quota

```bash
kubectl create namespace vc-limits

# Apply ResourceQuota + LimitRange to the HOST namespace
# This constrains the entire vcluster (control plane + synced pods)
kubectl apply -f host-namespace-quota.yaml -n vc-limits
```

### 2. Verify the quota is in place

```bash
kubectl describe namespace vc-limits
kubectl get resourcequota -n vc-limits
kubectl get limitrange -n vc-limits
```

### 3. Create the vcluster with defined control plane resources

```bash
vcluster create limits \
  --namespace vc-limits \
  --values vcluster-with-limits.yaml \
  --connect=false

kubectl rollout status statefulset/limits --namespace vc-limits --timeout=180s
```

### 4. Connect and deploy workloads inside the vcluster

```bash
vcluster connect limits --namespace vc-limits --update-current

# Deploy normal workloads within quota
kubectl apply -f workload-test.yaml

# Check the workloads
kubectl get pods -n quota-test
```

### 5. Apply a LimitRange inside the vcluster (tenant-enforced defaults)

```bash
# Inside the vcluster — set default resource requests/limits
kubectl apply -f - <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: quota-test
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 128Mi
      defaultRequest:
        cpu: 50m
        memory: 64Mi
      max:
        cpu: "1"
        memory: 512Mi
EOF
```

### 6. Try to exceed the quota

```bash
# Try to deploy a pod that requests too much memory
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: greedy-pod
  namespace: quota-test
spec:
  containers:
    - name: greedy
      image: nginx:alpine
      resources:
        requests:
          cpu: "10"      # Way over the quota
          memory: 100Gi
EOF

# Expected: pod gets stuck in Pending with Insufficient CPU/memory
kubectl describe pod greedy-pod -n quota-test | grep -A5 Events
```

### 7. Check quota usage from host perspective

```bash
vcluster disconnect

# Platform engineer can check how much of the quota is used
kubectl describe resourcequota -n vc-limits
```

### 8. Clean up

```bash
vcluster disconnect
vcluster delete limits --namespace vc-limits --delete-namespace
```

## Key Takeaways

1. **Host namespace quota** is the hard ceiling — the entire vcluster + its workloads cannot exceed it
2. **LimitRange inside vcluster** sets defaults so tenants don't accidentally create pods without resource requests
3. **vcluster control plane resources** should be sized explicitly in `vcluster-with-limits.yaml`
4. **No resources set = ResourceQuota admission failure** — always set requests when a quota is in place
5. Platform teams should set quotas before handing vclusters to tenants

## Recommended Sizing Guidelines

| Tenant Size | vcluster CP CPU | vcluster CP Memory | Namespace Quota |
|---|---|---|---|
| Small (1-2 devs) | 100m / 250m | 128Mi / 256Mi | 2 CPU / 2Gi |
| Medium (5-10 devs) | 200m / 500m | 256Mi / 512Mi | 4 CPU / 8Gi |
| Large (team) | 500m / 1000m | 512Mi / 1Gi | 8 CPU / 16Gi |

## Previous / Next

⬅️ [Demo 02 — Multi-Tenant vClusters](../02-multi-tenant/README.md)

➡️ [Demo 04 — Custom Sync Configuration](../04-custom-sync/README.md)
