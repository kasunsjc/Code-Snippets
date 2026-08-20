# AKS Desktop AI Troubleshooting Demo

Standalone demo for troubleshooting Kubernetes issues with AKS Desktop and its AI assistance. Each scenario is an independent YAML file so you can deploy and reset them one at a time during a live walkthrough.

## Goal

Create a small default AKS cluster and deploy intentionally broken workloads scenario by scenario. Use AKS Desktop and AI assistance to diagnose and fix each one.

## What gets deployed

- One default AKS cluster (standard managed cluster, not AKS Automatic)
- Per-scenario workloads under two namespaces:
  - `ai-demo` for basic scenarios
  - `ai-demo-advanced` for advanced scenarios

Workload names are neutral (product-style) so the AI has to diagnose the failure from events, logs, and object state, not from the name. Each YAML file has a header comment explaining the scenario and an inline comment at the failure site.

## Prerequisites

- Azure CLI logged in
- An Azure subscription with permissions to create resource groups and AKS clusters
- AKS Desktop installed locally
- `kubectl`

## Deploy the cluster

From this folder:

```bash
chmod +x deploy.sh
./deploy.sh
```

## Connect to AKS Desktop

1. Open AKS Desktop
2. Sign in with Azure
3. Add the cluster from your subscription
4. Open the cluster and pick the `ai-demo` or `ai-demo-advanced` namespace

## Folder layout

```text
scenarios/
  basic/
    01-image-pull-failure-broken.yaml         01-image-pull-failure-fixed.yaml
    02-crash-on-startup-broken.yaml           02-crash-on-startup-fixed.yaml
    03-unschedulable-pod-broken.yaml          03-unschedulable-pod-fixed.yaml
  advanced/
    01-configmap-missing-key-broken.yaml      01-configmap-missing-key-fixed.yaml
    02-service-port-mismatch-broken.yaml      02-service-port-mismatch-fixed.yaml
    03-service-selector-mismatch-broken.yaml  03-service-selector-mismatch-fixed.yaml
    04-readiness-probe-failing-broken.yaml    04-readiness-probe-failing-fixed.yaml
    05-pvc-missing-storageclass-broken.yaml   05-pvc-missing-storageclass-fixed.yaml
    06-oomkilled-low-memory-broken.yaml       06-oomkilled-low-memory-fixed.yaml
    07-cronjob-missing-secret-broken.yaml     07-cronjob-missing-secret-fixed.yaml
    08-networkpolicy-blocked-broken.yaml      08-networkpolicy-blocked-fixed.yaml
    09-rbac-missing-permissions-broken.yaml   09-rbac-missing-permissions-fixed.yaml
```

## Running a single scenario

Each scenario file is self-contained (namespace + workloads). Deploy just the one you want:

```bash
kubectl apply -f scenarios/basic/01-image-pull-failure-broken.yaml

# ... diagnose in AKS Desktop with the AI assistant ...

kubectl apply -f scenarios/basic/01-image-pull-failure-fixed.yaml
```

Same pattern for advanced scenarios:

```bash
kubectl apply -f scenarios/advanced/05-pvc-missing-storageclass-broken.yaml
# ...
kubectl apply -f scenarios/advanced/05-pvc-missing-storageclass-fixed.yaml
```

## Deploying and cleaning up in bulk

```bash
# deploy every broken scenario
for f in scenarios/basic/*-broken.yaml scenarios/advanced/*-broken.yaml; do
  kubectl apply -f "$f"
done

# apply every fix
for f in scenarios/basic/*-fixed.yaml scenarios/advanced/*-fixed.yaml; do
  kubectl apply -f "$f"
done

# wipe both demo namespaces
kubectl delete namespace ai-demo ai-demo-advanced --ignore-not-found
```

## Scenario reference

### Basic (namespace `ai-demo`)

| # | Broken file | Symptom | Root cause |
| - | ----------- | ------- | --------- |
| 1 | `01-image-pull-failure-broken.yaml` | `web-frontend` pod `ImagePullBackOff` | Image tag does not exist in the registry |
| 2 | `02-crash-on-startup-broken.yaml` | `order-service` pod `CrashLoopBackOff` | Container command exits non-zero on start |
| 3 | `03-unschedulable-pod-broken.yaml` | `notification-service` pod `Pending` | `nodeSelector` targets a hostname that does not exist |

### Advanced (namespace `ai-demo-advanced`)

| # | Broken file | Symptom | Root cause |
| - | ----------- | ------- | --------- |
| 1 | `01-configmap-missing-key-broken.yaml` | `payment-service` pod fails to start | `ConfigMap` `payment-config` is missing key `DB_URL` referenced by an env var |
| 2 | `02-service-port-mismatch-broken.yaml` | `catalog-probe` logs `connection refused` | `catalog-service` targetPort `3000` does not match container port `5678` |
| 3 | `03-service-selector-mismatch-broken.yaml` | `search-service` Service has no Endpoints | Service selector `app: search` does not match pod label `app: search-service` |
| 4 | `04-readiness-probe-failing-broken.yaml` | `checkout-service` pods `Running` but `0/1 Ready` | Readiness probe path `/ready` returns 404 on stock nginx |
| 5 | `05-pvc-missing-storageclass-broken.yaml` | `inventory-db-0` and PVC stay `Pending` | `storageClassName: fast-nvme-does-not-exist` |
| 6 | `06-oomkilled-low-memory-broken.yaml` | `analytics-worker` pod repeatedly `OOMKilled` | Memory limit `64Mi` far below the working set (~200Mi) |
| 7 | `07-cronjob-missing-secret-broken.yaml` | `report-job` pods `CreateContainerConfigError` | Referenced `Secret` `report-secrets` does not exist |
| 8 | `08-networkpolicy-blocked-broken.yaml` | `auth-client` logs curl timeouts | `NetworkPolicy` `auth-service-policy` denies all ingress with no allow rule |
| 9 | `09-rbac-missing-permissions-broken.yaml` | `cluster-inspector` logs show `Forbidden` | `ServiceAccount` `inspector-sa` has no `Role` / `RoleBinding` |

## Suggested AI troubleshooting prompts

Kept generic so the AI does the diagnosis:

```text
Look at namespace <ns> and report each unhealthy object with a root cause and a proposed fix.
Why is <workload> not ready? Read events and logs before answering.
Why does <service> have no endpoints even though the pods are running?
Trace the network path from <client> to <service> and explain why traffic is being dropped.
Why is the pod being OOMKilled? What limit should I set?
Why is this PVC stuck in Pending? Check the StorageClass.
Why is this Job failing with CreateContainerConfigError?
Why is the pod getting a 403 from the Kubernetes API?
Give me a prioritized remediation plan for this namespace.
```

## Handy diagnostic commands

```bash
kubectl get all,cm,secret,networkpolicy,serviceaccount,pvc -n ai-demo-advanced
kubectl get events -n ai-demo-advanced --sort-by=.lastTimestamp
kubectl describe pod -n ai-demo-advanced -l app=payment-service
kubectl logs -n ai-demo-advanced -l app=catalog-probe --tail=100
kubectl get endpoints -n ai-demo-advanced search-service
kubectl describe pvc -n ai-demo-advanced data-inventory-db-0
kubectl logs -n ai-demo-advanced -l app=cluster-inspector --tail=50
```

## Cleanup

```bash
chmod +x cleanup.sh
./cleanup.sh
```

## Demo narrative

- The workload appears unhealthy in AKS Desktop
- The AI assistant reads the events and logs
- The root cause is identified from evidence, not from the object name
- The corrected manifest is applied
- The workload recovers and becomes healthy
