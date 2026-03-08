# Kubernetes General Troubleshooting Prompt

You are troubleshooting a Kubernetes issue. Follow this systematic approach.

## Quick Health Check

```bash
# Cluster health
kubectl cluster-info
kubectl get componentstatuses 2>/dev/null || echo "componentstatuses deprecated in newer versions"
kubectl get nodes -o wide

# All unhealthy pods
kubectl get pods -A | grep -vE "Running|Completed"

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Resource utilization
kubectl top nodes
kubectl top pods -A --sort-by=cpu | head -20
```

## Pod Lifecycle Troubleshooting

### CrashLoopBackOff
```bash
# Get pod details and events
kubectl describe pod <POD> -n <NS>

# Check previous container logs
kubectl logs <POD> -n <NS> --previous --tail=200

# Check exit code
kubectl get pod <POD> -n <NS> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'

# Check resource limits vs actual usage
kubectl top pod <POD> -n <NS>
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.containers[0].resources}'
```

**Checklist:**
- [ ] Exit code 137? → Likely OOMKilled — increase memory limits
- [ ] Exit code 1? → Application error — check logs for stack traces
- [ ] Liveness probe failing? → Adjust probe thresholds or fix health endpoint
- [ ] Missing ConfigMap/Secret? → Verify all referenced configs exist
- [ ] Missing dependency? → Check if database, API, or queue is accessible

### ImagePullBackOff
```bash
# Check image reference
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.containers[*].image}'

# Check events for pull errors
kubectl get events -n <NS> --field-selector involvedObject.name=<POD>,reason=Failed

# Check image pull secrets
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.imagePullSecrets[*].name}'
kubectl get secret <SECRET> -n <NS> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

**Checklist:**
- [ ] Image tag exists in registry?
- [ ] Registry credentials configured (imagePullSecrets)?
- [ ] Network access to registry allowed?
- [ ] Image name spelled correctly (no typos)?

### Pending Pod
```bash
# Check scheduling events
kubectl describe pod <POD> -n <NS> | grep -A 20 "Events:"

# Check requested resources vs available
kubectl describe pod <POD> -n <NS> | grep -A 5 "Requests:"
kubectl describe nodes | grep -A 10 "Allocated resources"

# Check node selectors and affinity
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.nodeSelector}'
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.affinity}'

# Check taints and tolerations
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.tolerations}'

# Check PVC status
kubectl get pvc -n <NS>
```

**Checklist:**
- [ ] Sufficient CPU/memory on nodes?
- [ ] Node selector matches existing node labels?
- [ ] Pod tolerates node taints?
- [ ] PVCs are bound?
- [ ] Resource quota exceeded?

### Init Container Issues
```bash
# Check init container status
kubectl get pod <POD> -n <NS> -o jsonpath='{.status.initContainerStatuses}' | jq .

# Init container logs
kubectl logs <POD> -n <NS> -c <INIT_CONTAINER_NAME>
```

## Deployment & ReplicaSet Issues

```bash
# Deployment status
kubectl get deploy <DEPLOY> -n <NS> -o wide
kubectl describe deploy <DEPLOY> -n <NS>

# Rollout status
kubectl rollout status deploy/<DEPLOY> -n <NS>
kubectl rollout history deploy/<DEPLOY> -n <NS>

# ReplicaSet details
kubectl get rs -n <NS> -l app=<APP_LABEL>
kubectl describe rs <RS_NAME> -n <NS>

# ⚠️ Rollback (mutating)
# kubectl rollout undo deploy/<DEPLOY> -n <NS>
# kubectl rollout undo deploy/<DEPLOY> -n <NS> --to-revision=<N>
```

## Service & Networking

```bash
# Service details
kubectl get svc <SVC> -n <NS> -o wide
kubectl describe svc <SVC> -n <NS>

# Endpoints (must show pod IPs for traffic to flow)
kubectl get endpoints <SVC> -n <NS>

# Compare service selector with pod labels
kubectl get svc <SVC> -n <NS> -o jsonpath='{.spec.selector}'
kubectl get pods -n <NS> --show-labels

# DNS resolution test
kubectl run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --rm -it --restart=Never -- nslookup <SVC>.<NS>.svc.cluster.local

# Connectivity test
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- curl -sv http://<SVC>.<NS>.svc.cluster.local:<PORT>

# Ingress details
kubectl get ingress -n <NS>
kubectl describe ingress <INGRESS> -n <NS>

# Ingress controller logs
kubectl logs -n <INGRESS_NS> -l app.kubernetes.io/name=ingress-nginx --tail=100
```

**Service Checklist:**
- [ ] Service selector matches pod labels?
- [ ] Endpoints list shows pod IPs? (empty = selector mismatch or no ready pods)
- [ ] Target port matches container port?
- [ ] Network policies allow traffic?
- [ ] Pods are in Ready state?

## Storage

```bash
# PV/PVC overview
kubectl get pv
kubectl get pvc -n <NS>
kubectl describe pvc <PVC> -n <NS>

# Storage classes
kubectl get sc
kubectl describe sc <SC_NAME>

# Check if PV is stuck in Released state
kubectl get pv | grep Released

# Check volume mounts in pod
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.volumes}' | jq .
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.containers[*].volumeMounts}' | jq .
```

## RBAC & Security

```bash
# Test permissions
kubectl auth can-i <VERB> <RESOURCE> -n <NS>
kubectl auth can-i create pods -n default
kubectl auth can-i --list -n <NS>

# As a specific user/service account
kubectl auth can-i <VERB> <RESOURCE> -n <NS> --as=system:serviceaccount:<NS>:<SA>

# List roles and bindings
kubectl get roles,rolebindings -n <NS>
kubectl get clusterroles,clusterrolebindings

# Service account details
kubectl get sa <SA> -n <NS> -o yaml
```

## Resource Quotas & Limits

```bash
# Check quotas
kubectl get resourcequota -n <NS>
kubectl describe resourcequota -n <NS>

# Check limit ranges
kubectl get limitrange -n <NS>
kubectl describe limitrange -n <NS>

# Current namespace usage
kubectl get resourcequota -n <NS> -o jsonpath='{.items[*].status}'
```

## Jobs & CronJobs

```bash
# Job status
kubectl get jobs -n <NS>
kubectl describe job <JOB> -n <NS>
kubectl get pods -n <NS> -l job-name=<JOB>

# CronJob status
kubectl get cronjobs -n <NS>
kubectl describe cronjob <CRONJOB> -n <NS>

# Check failed jobs
kubectl get jobs -n <NS> --field-selector status.successful=0
```

## ConfigMaps & Secrets

```bash
# List and inspect
kubectl get configmap -n <NS>
kubectl describe configmap <CM> -n <NS>

kubectl get secrets -n <NS>
kubectl describe secret <SECRET> -n <NS>

# Check if ConfigMap/Secret is mounted correctly
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.volumes[*]}' | jq .
kubectl exec <POD> -n <NS> -- ls /path/to/mount/
kubectl exec <POD> -n <NS> -- env | grep <EXPECTED_VAR>
```

## Helm Troubleshooting

```bash
# List releases
helm list -A

# Release status
helm status <RELEASE> -n <NS>
helm history <RELEASE> -n <NS>

# Get rendered manifests
helm get manifest <RELEASE> -n <NS>
helm get values <RELEASE> -n <NS>

# ⚠️ Rollback (mutating)
# helm rollback <RELEASE> <REVISION> -n <NS>
```

## Monitoring & Metrics

```bash
# Metrics server check
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get pods -n kube-system | grep metrics-server

# HPA status
kubectl get hpa -A
kubectl describe hpa <HPA> -n <NS>

# VPA status (if installed)
kubectl get vpa -A

# Pod Disruption Budgets
kubectl get pdb -A
kubectl describe pdb <PDB> -n <NS>
```
