# Kyverno Policy Deployment and Verification Guide

This guide explains what each policy does, how to deploy policies manually, and how to verify that each policy is active and working correctly.

## Prerequisites

Run infrastructure setup first:

```bash
./deploy.sh
```

Confirm Kyverno is healthy:

```bash
kubectl get pods -n kyverno
kubectl rollout status deployment/kyverno-admission-controller -n kyverno
```

## Manual Policy Deployment

From the `Kyverno-Policy-Demo` folder, apply policies by category.

### 1. Validation policies

```bash
kubectl apply -f policies/01-validation/
```

### 2. Mutation policies

```bash
kubectl apply -f policies/02-mutation/
```

### 3. Generation policies

```bash
kubectl apply -f policies/03-generation/
```

### 4. Cleanup policies

```bash
kubectl apply -f policies/04-cleanup/
```

Check what was created:

```bash
kubectl get clusterpolicies
kubectl get clustercleanuppolicies
```

## What Each Policy Does

## Validation policies

### `disallow-privileged-containers`
- Category: Validation
- Mode: `Enforce`
- Effect: Blocks pods where any container has `securityContext.privileged: true`.
- Why: Prevents elevated container privilege.

### `disallow-host-namespaces`
- Category: Validation
- Mode: `Enforce`
- Effect: Blocks pods that set `hostPID`, `hostIPC`, or `hostNetwork`.
- Why: Prevents host namespace sharing and reduces lateral movement risk.

### `disallow-latest-tag`
- Category: Validation
- Mode: `Enforce`
- Effect: Blocks images tagged `:latest`.
- Why: Encourages immutable and predictable deployments.

### `require-resource-limits`
- Category: Validation
- Mode: `Enforce`
- Effect: Requires CPU and memory requests and limits for every container.
- Why: Prevents noisy-neighbor issues and stabilizes scheduling.

### `require-pod-labels`
- Category: Validation
- Mode: `Enforce`
- Effect: Requires `app`, `version`, and `owner` labels.
- Why: Improves ownership, reporting, and selection consistency.

## Mutation policies

### `add-default-labels`
- Category: Mutation
- Effect: Adds default labels and metadata annotations if missing.
- Why: Ensures baseline metadata consistency across workloads.

### `add-security-context`
- Category: Mutation
- Effect: Adds secure defaults such as `allowPrivilegeEscalation: false` and `runAsNonRoot: true` when absent.
- Why: Applies safer defaults without forcing developers to set everything manually.

### `add-default-resource-limits`
- Category: Mutation
- Effect: Adds default requests and limits if missing.
- Why: Helps keep workloads schedulable and controlled.

## Generation policies

### `generate-default-network-policy`
- Category: Generation
- Effect: For each new namespace (except excluded system namespaces), creates default network policies.
- Why: Enforces namespace isolation posture by default.

### `generate-namespace-resource-quota`
- Category: Generation
- Effect: For each new namespace (except excluded system namespaces), creates a default `ResourceQuota`.
- Why: Prevents unbounded namespace consumption.

## Cleanup policy

### `cleanup-completed-jobs`
- Category: Cleanup
- Schedule: Every 6 hours
- Effect: Deletes completed `Job` resources matching policy conditions.
- Why: Reduces stale workload artifacts over time.

## How to Verify Policies Are Applied Properly

Use both control-plane checks and behavior checks.

### A. Control-plane checks (installed and ready)

```bash
kubectl get clusterpolicies
kubectl describe clusterpolicy disallow-privileged-containers
kubectl describe clusterpolicy add-default-labels
kubectl get clustercleanuppolicies
kubectl describe clustercleanuppolicy cleanup-completed-jobs
```

What to confirm:
- Policy exists.
- `READY` is `True` where shown.
- No webhook/schema errors in `kubectl describe` output.

### B. Admission behavior checks (does it enforce/mutate/generate)

## Validation checks

Run these tests and expect the results shown.

```bash
kubectl apply -f sample-apps/01-compliant-pod.yaml
```
Expected: allowed.

```bash
kubectl apply -f sample-apps/02-non-compliant-privileged.yaml
```
Expected: denied by `disallow-privileged-containers`.

```bash
kubectl apply -f sample-apps/03-non-compliant-no-limits.yaml
```
Expected: denied by `require-resource-limits`.

```bash
kubectl apply -f sample-apps/04-non-compliant-latest-tag.yaml
```
Expected: denied by `disallow-latest-tag`.

```bash
kubectl apply -f sample-apps/05-non-compliant-missing-labels.yaml
```
Expected: denied by `require-pod-labels`.

## Mutation checks

```bash
kubectl apply -f sample-apps/06-mutation-test-pod.yaml
kubectl get pod mutation-test -n demo -o yaml
```

Expected: injected labels/annotations/securityContext fields appear on the stored object.

## Generation checks

```bash
kubectl apply -f sample-apps/07-generation-test-namespace.yaml
kubectl get networkpolicy -n kyverno-demo-ns
kubectl get resourcequota -n kyverno-demo-ns
```

Expected: generated policies and quota exist.

## Cleanup checks

```bash
kubectl apply -f sample-apps/08-cleanup-test-job.yaml
kubectl get jobs -n demo
kubectl describe clustercleanuppolicy cleanup-completed-jobs
```

Expected: job completes and is removed on cleanup schedule.

### C. Reporting and events checks

```bash
kubectl get policyreport -A
kubectl get clusterpolicyreport
kubectl get events -A --field-selector reason=PolicyViolation
```

### D. Kyverno logs checks

```bash
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno-admission-controller --tail=100
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno-background-controller --tail=100
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno-cleanup-controller --tail=100
```

If a policy does not behave as expected, these logs are usually the fastest root-cause source.

## Optional: Fast end-to-end test script

After manually deploying policies, you can run:

```bash
./sample-apps/test-policies.sh
```

This validates expected allow/deny and generation behavior with PASS/FAIL output.
