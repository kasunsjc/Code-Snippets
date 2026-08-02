# k6 Operator Setup

This folder installs only the k6 Operator and its namespace prerequisites.

## Files

- `install.sh`: installs/upgrades k6 Operator via Helm
- `namespace.yaml`: creates `k6-tests` namespace

## Install

```bash
bash k6-operator/install.sh
```

## Verify

```bash
kubectl get pods -n k6-operator
kubectl api-resources | grep -i testrun
```
