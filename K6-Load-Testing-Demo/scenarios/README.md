# Scenario Guide

Each scenario folder contains:

- `configmap.yaml`: k6 JavaScript script
- `testrun.yaml`: k6 Operator TestRun definition

## Available Scenarios

- `01-smoke-test`: quick sanity check
- `02-load-test`: steady baseline load
- `03-stress-test`: increasing pressure with distributed runners
- `04-spike-test`: abrupt traffic bursts
- `05-soak-test`: longer run for stability checks
- `06-breakpoint-test`: pushes limits with abort thresholds
- `07-advanced`: groups, custom metrics, and summary output

## Run Any Scenario

```bash
kubectl apply -f scenarios/<scenario-folder>/
kubectl get testrun -n k6-tests -w
kubectl logs -n k6-tests -l k6_cr=<testrun-name> -f
```

## Remove a Scenario Run

```bash
kubectl delete testrun <testrun-name> -n k6-tests
```
