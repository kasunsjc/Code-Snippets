# Demo 04 — Custom Sync Configuration

One of the most powerful vcluster features is its **sync engine** — the bridge between the virtual cluster and the host cluster. This demo dives into what gets synced by default, how to enable additional synced resources, and how to sync objects from the host INTO the vcluster.

## Learning Objectives

- Understand the vcluster sync architecture (toHost vs fromHost)
- Enable syncing of additional resource types (Ingresses, PVCs, NetworkPolicies)
- Sync ConfigMaps and Secrets from the host into the vcluster (fromHost)
- Understand what **does not** sync by default and why
- Use custom sync patches to rename/rewrite synced fields

## Concepts Explained

### Sync Direction

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   vcluster (virtual)      ──── toHost ────►  Host namespace │
│                                                             │
│   Pod, Service,           sync to host for actual scheduling│
│   Ingress (opt),                                            │
│   PVC (opt), NetworkPolicy (opt)                            │
│                                                             │
│   vcluster (virtual)      ◄─── fromHost ────  Host cluster  │
│                                                             │
│   Nodes, StorageClasses,  read from host into vcluster     │
│   IngressClasses,                                           │
│   ConfigMaps (opt),                                         │
│   Secrets (opt)                                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Default Sync Behaviour (vcluster v0.20+)

| Resource | Direction | Default | Notes |
|---|---|---|---|
| Pods | toHost | ✅ Always | Core functionality |
| Services | toHost | ✅ Always | ClusterIP synced |
| Endpoints | toHost | ✅ Always | |
| ConfigMaps | toHost | ✅ Default | |
| Secrets | toHost | ✅ Default | |
| PersistentVolumeClaims | toHost | ✅ Default | |
| Ingresses | toHost | ❌ Off | Enable explicitly |
| NetworkPolicies | toHost | ❌ Off | Enable explicitly |
| Nodes | fromHost | ✅ Default | Virtual nodes |
| StorageClasses | fromHost | ✅ Default | |
| IngressClasses | fromHost | ❌ Off | Enable explicitly |
| ConfigMaps (host→vcluster) | fromHost | ❌ Off | Useful for shared config |
| Secrets (host→vcluster) | fromHost | ❌ Off | Useful for shared secrets |

## Files

| File | Purpose |
|---|---|
| [sync-values.yaml](sync-values.yaml) | vcluster config with extended sync enabled |
| [test-configmap.yaml](test-configmap.yaml) | ConfigMap created on HOST to sync into vcluster |
| [test-secret-host.yaml](test-secret-host.yaml) | Secret on HOST to sync into vcluster |
| [setup-sync.sh](setup-sync.sh) | Full automated walkthrough |

## Step-by-Step Walkthrough

### 1. Create a vcluster with extended sync enabled

```bash
kubectl create namespace vc-sync

vcluster create sync \
  --namespace vc-sync \
  --values sync-values.yaml \
  --connect=false

kubectl rollout status statefulset/sync --namespace vc-sync --timeout=180s
```

### 2. Create shared resources on the HOST first

```bash
# This ConfigMap lives on the HOST cluster
# It will be synced INTO the vcluster via fromHost sync
kubectl apply -f test-configmap.yaml -n vc-sync
kubectl apply -f test-secret-host.yaml -n vc-sync
```

### 3. Connect and verify fromHost sync

```bash
vcluster connect sync --namespace vc-sync --update-current

# Check if the shared ConfigMap appeared inside the vcluster
kubectl get configmap shared-platform-config -n kube-system

# Check the shared secret
kubectl get secret shared-platform-secret -n kube-system
```

### 4. Test toHost sync for Ingresses

```bash
# Deploy an app with an Ingress inside the vcluster
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: sync-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  namespace: sync-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
        - name: echo
          image: ealen/echo-server:latest
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: echo-server
  namespace: sync-test
spec:
  selector:
    app: echo
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-ingress
  namespace: sync-test
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: echo.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: echo-server
                port:
                  number: 80
EOF
```

### 5. Verify Ingress is synced to the HOST

```bash
# Inside vcluster — Ingress exists with original name
kubectl get ingress -n sync-test

# Disconnect and check on the HOST
vcluster disconnect

# On the HOST — Ingress appears in the vc-sync namespace with a mangled name
kubectl get ingress -n vc-sync
```

### 6. Clean up

```bash
vcluster disconnect
vcluster delete sync --namespace vc-sync --delete-namespace
```

## Key Takeaways

1. **Default sync** covers the most common resources (Pods, Services, PVCs, ConfigMaps, Secrets)
2. **Ingress sync** must be enabled explicitly — this lets the host's Ingress controller serve virtual cluster routes
3. **fromHost ConfigMap/Secret sync** is ideal for platform-level shared configs (e.g. cluster CA, DNS settings)
4. **StorageClass sync** means vclusters automatically see the host's storage classes
5. **Sync patches** (advanced) let you rewrite synced field values (e.g. image registries, annotations)

## Advanced: Sync Patches

vcluster supports patching synced resources on-the-fly. For example, rewriting container images to use a private registry:

```yaml
sync:
  toHost:
    pods:
      rewriteHosts:
        enabled: true
      patches:
        - op: rewriteImage
          path: .spec.containers[*].image
          regex: "^docker.io/(.*)"
          replace: "myregistry.azurecr.io/$1"
```

## Previous / Next

⬅️ [Demo 03 — Resource Limits & Isolation](../03-resource-limits/README.md)

➡️ [Demo 05 — Ingress & Networking](../05-ingress-networking/README.md)
