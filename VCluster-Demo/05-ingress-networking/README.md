# Demo 05 — Ingress & Networking

In this demo you will connect a vcluster to the host cluster's **NGINX Ingress Controller**, expose an application running inside a vcluster to the internet using a real Ingress, and explore how networking flows between the virtual and host cluster layers.

## Learning Objectives

- Install the NGINX Ingress Controller on the host AKS cluster
- Configure a vcluster to sync Ingresses to the host
- Expose a vcluster application via a host-level LoadBalancer
- Understand how DNS and traffic routing work through the vcluster sync layer
- Use `ExternalName` services to reach host-cluster services from inside a vcluster

## Concepts Explained

### Ingress Traffic Flow

```
Internet
    │
    ▼
[Azure Load Balancer]  (host cluster — created by NGINX IC)
    │
    ▼
[NGINX Ingress Controller Pod]  (running on host, in ingress-nginx namespace)
    │
    │  Routes by Host header: echo.yourdomain.com
    │
    ▼
[Synced Service in vc-ingress namespace]  (host namespace = vcluster ns)
    │
    │  vcluster syncs the pod endpoint to the synced service
    │
    ▼
[echo-server Pod]  (actual workload pod, running on host node)
```

### Key Points

- The **Ingress resource** lives in the vcluster (tenant-managed)
- vcluster syncs it to the **host namespace** with a unique name prefix
- The host **Ingress controller** reads it and configures routing
- The workload **pods** run on host nodes (via sync), so Ingress → Pod routing works normally

## Files

| File | Purpose |
|---|---|
| [ingress-values.yaml](ingress-values.yaml) | vcluster config with Ingress sync enabled |
| [install-nginx-ingress.sh](install-nginx-ingress.sh) | Install NGINX Ingress Controller on host |
| [ingress-app.yaml](ingress-app.yaml) | Sample app with Ingress, deployed inside vcluster |
| [setup-ingress.sh](setup-ingress.sh) | Full automated walkthrough |

## Step-by-Step Walkthrough

### 1. Install NGINX Ingress Controller on the host

```bash
# This installs the NGINX Ingress Controller on the HOST cluster
# It creates a LoadBalancer service that gets an Azure Public IP
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Wait for LoadBalancer IP
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Get the external IP
kubectl get service ingress-nginx-controller -n ingress-nginx
```

### 2. Get the External IP

```bash
EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "External IP: $EXTERNAL_IP"
# Use this IP with nip.io for easy DNS-less testing
# e.g. echo.$EXTERNAL_IP.nip.io will resolve to $EXTERNAL_IP
```

### 3. Create the vcluster with Ingress sync

```bash
kubectl create namespace vc-ingress

vcluster create ingress \
  --namespace vc-ingress \
  --values ingress-values.yaml \
  --connect=false

kubectl rollout status statefulset/ingress --namespace vc-ingress --timeout=180s
```

### 4. Deploy the app with Ingress inside the vcluster

```bash
vcluster connect ingress --namespace vc-ingress --update-current

# Get the external IP (from step 2) and create a nip.io host
EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  --context $(kubectl config get-contexts -o name | grep -v vcluster | head -1) \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "PENDING")

HOST="echo.${EXTERNAL_IP}.nip.io"
echo "Will use host: $HOST"

# Deploy app with Ingress
cat ingress-app.yaml | sed "s/REPLACE_WITH_HOST/$HOST/g" | kubectl apply -f -

kubectl rollout status deployment/echo-server -n ingress-test --timeout=120s
```

### 5. Test the Ingress

```bash
# Test from outside the cluster
curl -H "Host: $HOST" "http://$EXTERNAL_IP"

# Or if using a real DNS hostname:
curl "http://$HOST"
```

### 6. Observe sync on the host

```bash
vcluster disconnect

# The Ingress resource appears on the host in the vcluster namespace
kubectl get ingress -n vc-ingress

# The synced service also appears on the host
kubectl get service -n vc-ingress
```

### 7. Reach host cluster services from inside vcluster (ExternalName)

```bash
vcluster connect ingress --namespace vc-ingress --update-current

# Create an ExternalName service that points to a host-cluster service
# e.g. reach the NGINX Ingress controller's status from inside vcluster
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: host-nginx-status
  namespace: ingress-test
spec:
  type: ExternalName
  externalName: ingress-nginx-controller.ingress-nginx.svc.cluster.local
  ports:
    - port: 10254
EOF

# Now reach it from inside the vcluster
kubectl exec -n ingress-test deploy/echo-server -- \
  curl -s http://host-nginx-status.ingress-test.svc.cluster.local:10254/healthz
```

### 8. Clean up

```bash
vcluster disconnect
vcluster delete ingress --namespace vc-ingress --delete-namespace
# Optionally remove NGINX IC
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```

## Key Takeaways

1. **NGINX IC lives on the host** — vclusters reuse the host's ingress controller
2. **Ingress sync** makes this transparent to tenants — they create Ingresses in their vcluster normally
3. **nip.io** is perfect for demo/testing without real DNS
4. **ExternalName services** bridge vcluster to host-cluster services
5. **LoadBalancer services** inside vclusters are also synced (creates host LoadBalancer)

## Networking Deep Dive

| Scenario | How it works |
|---|---|
| Pod-to-Pod (same vcluster) | Direct pod networking via host CNI |
| Pod-to-Service (same vcluster) | kube-proxy on host handles it (synced service) |
| Ingress to vcluster pod | Host IC → synced service → synced pod endpoint |
| vcluster to host service | ExternalName service pointing to host DNS |
| Pod-to-Pod (cross vcluster) | Not possible by default (isolation); use host services |

## Previous / Next

⬅️ [Demo 04 — Custom Sync Configuration](../04-custom-sync/README.md)

⬆️ [Back to Main README](../README.md)
