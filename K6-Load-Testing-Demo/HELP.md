# K6 Demo Help

This guide is for quick troubleshooting while running the AKS k6 demo.

## Common Checks

```bash
kubectl get ns
kubectl get pods -A
kubectl get testrun -n k6-tests
```

## TestRun Stuck or Failing

```bash
kubectl describe testrun smoke-test -n k6-tests
kubectl get pods -n k6-tests -o wide
kubectl logs -n k6-tests -l k6_cr=smoke-test --tail=200
```

## Scenario Re-run

```bash
kubectl delete testrun smoke-test -n k6-tests --ignore-not-found
kubectl apply -f scenarios/01-smoke-test/
```

## Verify Target App

```bash
kubectl get pods -n demo-apps
kubectl get svc -n demo-apps
kubectl run curlbox --rm -it --image=curlimages/curl:8.9.1 --restart=Never -- \
  curl -sS http://httpbin.demo-apps.svc.cluster.local/get
```

## Remove All TestRuns

```bash
kubectl delete testrun --all -n k6-tests
```

## Reset Demo

```bash
./cleanup.sh
./deploy.sh
```
