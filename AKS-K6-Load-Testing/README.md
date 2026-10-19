# Load Testing AKS Applications with k6

Deploy a small HTTP API to AKS and load test it locally or in-cluster with the k6 Operator.

## What you'll deploy

- A three-replica Node.js HTTP API exposed by a Kubernetes `LoadBalancer` service.
- A k6 test with ramp-up, steady-state, and ramp-down stages, checks, thresholds, and custom metrics.
- Optionally, the official Grafana k6 Operator to run the test from inside AKS.

## Prerequisites

- An AKS cluster and an Azure CLI login with permission to deploy Kubernetes resources.
- `kubectl` configured for the cluster.
- [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/) for local execution.
- [Helm](https://helm.sh/docs/intro/install/) for the optional k6 Operator.

## Deploy the sample API

```bash
kubectl create namespace k6-demo
kubectl apply -f k8s/target-app.yaml
kubectl rollout status deployment/target-app -n k6-demo
kubectl get service target-app -n k6-demo
```

The service is a public Azure Load Balancer. Wait for `EXTERNAL-IP` to be assigned before running the local test. To avoid public exposure, change the service type to `ClusterIP` and use `kubectl port-forward service/target-app 8080:80 -n k6-demo` instead.

## Option A: Run k6 locally

Use the external IP from the service above:

```bash
BASE_URL="http://<EXTERNAL-IP>" k6 run k6/load-test.js
```

For a `ClusterIP` service accessed through the port-forward alternative, run the port-forward command in another terminal and set `BASE_URL="http://localhost:8080"`.

The default k6 summary is printed in the terminal. The test fails if the 95th percentile request latency reaches 200 ms or the HTTP failure rate reaches 1%.

## Option B: Run with the k6 Operator

Install the official Grafana Helm chart:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install k6-operator grafana/k6-operator \
  --namespace k6-operator-system \
  --create-namespace
```

Create a ConfigMap from the same test script and start the distributed test:

```bash
kubectl create configmap k6-test-script \
  --from-file=test.js=k6/load-test.js \
  --namespace k6-demo \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/k6-test-run.yaml
kubectl get testruns -n k6-demo
kubectl describe testrun distributed-load-test -n k6-demo
kubectl get pods -n k6-demo
```

The `TestRun` starts four runner pods. They access the API through its in-cluster service DNS name. Follow a runner's output with `kubectl logs -n k6-demo <runner-pod>`.

## Metrics and observability

The local run prints the standard k6 summary, including the configured latency and failure-rate thresholds and the custom `product_latency` Trend and `product_requests` Counter. To send metrics to a Prometheus-compatible remote-write endpoint, configure its endpoint and authentication and run:

```bash
k6 run --out experimental-prometheus-rw k6/load-test.js
```

For Azure Monitor Managed Prometheus, configure the supported remote-write ingestion endpoint and Azure authentication for the runner, then view the workspace as a data source in Azure Managed Grafana. Do not put credentials in the manifests. The operator runners need the same remote-write output configuration; the default manifests only show the k6 CLI summary.

## Clean up

```bash
kubectl delete -f k8s/k6-test-run.yaml --ignore-not-found
kubectl delete namespace k6-demo
helm uninstall k6-operator --namespace k6-operator-system
kubectl delete namespace k6-operator-system
```

Deleting the `k6-demo` namespace removes the sample API, service, and test ConfigMap. Uninstalling the Helm release removes the operator and its resources.
