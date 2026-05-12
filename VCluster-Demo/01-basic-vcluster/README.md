# Demo 01 — Getting Started with vcluster

This is the starting point for learning vcluster. You will create your first virtual cluster, deploy an application inside it, and discover how isolation works between the virtual cluster and the host AKS cluster.

## Learning Objectives

- Understand what a vcluster is and how it differs from a namespace
- Create a vcluster using the CLI with a custom config file
- Deploy and access workloads inside a vcluster
- Observe the syncing behaviour between vcluster and host
- Switch kubectl context between host and virtual cluster

## Concepts Explained

### What is a vcluster?

A **virtual cluster** (vcluster) is a fully functional Kubernetes cluster running *inside* a namespace of a host Kubernetes cluster. It has its own:

- API server (runs as a Pod in the host namespace)
- Controller manager
- etcd (or sqlite/embedded DB for lightweight setups)
- Separate kubeconfig and RBAC

```
┌─────────────────────────────────────────────────────┐
│  Host AKS Cluster                                   │
│                                                     │
│  Namespace: vc-basic                                │
│  ┌───────────────────────────────────────────────┐  │
│  │  vcluster (k3s)                               │  │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐  │  │
│  │  │ API Srv  │  │  CM      │  │  etcd     │  │  │
│  │  └──────────┘  └──────────┘  └───────────┘  │  │
│  │                                               │  │
│  │  Virtual Namespaces:                          │  │
│  │    default, kube-system, demo-app             │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Synced Pods (visible on host as                    │
│  mangled-name pods in vc-basic namespace)           │
└─────────────────────────────────────────────────────┘
```

### Pod Syncing

vcluster does NOT run pods inside the virtual control plane. Instead, it **syncs** pod specs to the host cluster namespace. This means:

| Virtual Cluster | Host Cluster Namespace (vc-basic) |
|---|---|
| `demo-app/nginx-demo-xxx` | `nginx-demo-xxx-x-demo-app-x-basic` |
| `default/my-pod` | `my-pod-x-default-x-basic` |

The pods run on the **host nodes** but are only visible (with their original names) from inside the vcluster.

## Prerequisites

1. Host AKS cluster deployed (run `../deploy.sh`)
2. vcluster CLI installed (run `../install-tools.sh`)
3. kubectl context pointing to the host AKS cluster

## Files

| File | Purpose |
|---|---|
| [vcluster-values.yaml](vcluster-values.yaml) | vcluster configuration (k3s distro, sync settings) |
| [demo-app.yaml](demo-app.yaml) | nginx deployment + service to test inside vcluster |
| [create-vcluster.sh](create-vcluster.sh) | Full automated walkthrough script |

## Step-by-Step Walkthrough

### 1. Create the vcluster

```bash
# Create a dedicated namespace on the host
kubectl create namespace vc-basic

# Create the vcluster using k3s distro with our custom config
vcluster create basic \
  --namespace vc-basic \
  --values vcluster-values.yaml \
  --connect=false
```

### 2. Check what the HOST cluster sees

```bash
# On the HOST — you see only the vcluster control plane pod
kubectl get pods -n vc-basic

# Expected output:
# NAME      READY   STATUS    RESTARTS   AGE
# basic-0   1/1     Running   0          90s
```

### 3. Connect to the vcluster

```bash
# Connect — this updates your kubeconfig with a new context
vcluster connect basic --namespace vc-basic --update-current

# Verify you are now inside the vcluster
kubectl config current-context
# Output: vcluster_basic_vc-basic_<cluster>

# List nodes — these are the HOST nodes but visible inside vcluster
kubectl get nodes

# List namespaces — clean Kubernetes installation
kubectl get namespaces
```

### 4. Deploy an app inside the vcluster

```bash
kubectl apply -f demo-app.yaml

# Watch the pods come up
kubectl get pods -n demo-app -w

# Test DNS and connectivity
kubectl exec -n demo-app verify-pod -- \
  curl -s http://nginx-demo.demo-app.svc.cluster.local
```

### 5. Compare views — vcluster vs host

```bash
# Inside vcluster: you see demo-app namespace
kubectl get namespaces

# Disconnect back to host
vcluster disconnect

# On the HOST: demo-app namespace does NOT exist
kubectl get namespace demo-app  # Error: not found

# On the HOST: but the nginx pods DO appear (synced) in vc-basic namespace
kubectl get pods -n vc-basic
# You will see nginx pods with mangled names like:
# nginx-demo-xxx-x-demo-app-x-basic
```

### 6. Port-forward to access nginx

```bash
# Connect to vcluster first
vcluster connect basic --namespace vc-basic --update-current

# Port-forward the service
kubectl port-forward -n demo-app svc/nginx-demo 8080:80

# Open in browser: http://localhost:8080
```

### 7. Clean up this demo

```bash
# Disconnect first if still connected
vcluster disconnect

# Delete the vcluster and its namespace
vcluster delete basic --namespace vc-basic --delete-namespace
```

## Key Takeaways

1. **Isolation** — Namespaces, RBAC, and workloads inside a vcluster are invisible on the host
2. **Syncing** — Pods are actually scheduled on host nodes (synced transparently)
3. **Kubeconfig** — `vcluster connect/disconnect` switches your kubectl context
4. **Lightweight** — The entire control plane is just one StatefulSet pod on the host
5. **Portable** — vcluster can run on any Kubernetes cluster (AKS, EKS, GKE, kind, k3d)

## Troubleshooting

| Problem | Solution |
|---|---|
| `vcluster create` times out | Check `kubectl get pods -n vc-basic` and describe failing pods |
| `vcluster connect` fails | Ensure the StatefulSet is Running; check host firewall rules |
| Pods stuck in `Pending` inside vcluster | Host user node pool may need scale-out; check node capacity |
| `demo-app` namespace not found | You may be on the host context; run `vcluster connect basic -n vc-basic` |

## Next Demo

➡️ [Demo 02 — Multi-Tenant vClusters](../02-multi-tenant/README.md)
