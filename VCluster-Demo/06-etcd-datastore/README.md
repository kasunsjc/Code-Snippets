# Demo 06 — vcluster with Embedded etcd Backing Store

## Overview

By default, vcluster stores all Kubernetes state in an **embedded SQLite database** — a single file inside the control plane pod. This is perfectly fine for short-lived development environments, but has limitations:

| Feature | SQLite (default) | Embedded etcd (this demo) |
|---------|-----------------|--------------------------|
| Single replica only | ✓ | ✗ (HA supported) |
| High Availability | ✗ | ✓ (3+ replicas) |
| Durable storage (PVC) | Optional | Strongly recommended |
| Production-ready | Dev/CI only | Yes |
| Memory per replica | ~10–30 MB | ~50–100 MB |
| etcd health tooling | ✗ | ✓ |

This demo shows how to configure embedded etcd, run 3 HA replicas, and verify that state is preserved across control plane restarts.

---

## Files

| File | Purpose |
|------|---------|
| `etcd-values.yaml` | vcluster values with embedded etcd + HA enabled |
| `test-persistence.yaml` | StatefulSet + PVC deployed inside the vcluster |
| `setup-etcd-demo.sh` | End-to-end demo script |
| `cleanup-etcd.sh` | Removes all resources created by this demo |

---

## Prerequisites

- Host AKS cluster running — run `../deploy.sh` if not already done
- `vcluster` CLI installed — run `../install-tools.sh`
- `kubectl` pointing to the host AKS cluster

---

## Running the Demo

```bash
# Make scripts executable (first time only)
chmod +x setup-etcd-demo.sh cleanup-etcd.sh

# Run the full demo
./setup-etcd-demo.sh
```

To clean up when done:

```bash
./cleanup-etcd.sh
```

---

## How It Works

### 1. Enabling Embedded etcd

The key configuration in `etcd-values.yaml`:

```yaml
controlPlane:
  backingStore:
    embeddedEtcd:
      enabled: true       # replaces SQLite with etcd
  statefulSet:
    highAvailability:
      replicas: 3         # 3 etcd members = tolerates 1 failure
  persistence:
    volumeClaim:
      enabled: true       # each replica gets a PVC
      size: 5Gi
```

When vcluster sees `embeddedEtcd.enabled: true` it:
1. Deploys 3 StatefulSet pods (not 1)
2. Starts an etcd member inside each pod alongside the k3s API server
3. Creates a `PersistentVolumeClaim` per pod so etcd WAL files survive restarts

### 2. High Availability Behaviour

With 3 replicas, the etcd cluster can tolerate **1 node failure** while maintaining quorum (majority = 2 of 3). The vcluster API server load-balances across healthy members.

```
Pod 0: [k3s API server] + [etcd member 0]  ←── PVC 0 (Azure Disk)
Pod 1: [k3s API server] + [etcd member 1]  ←── PVC 1 (Azure Disk)
Pod 2: [k3s API server] + [etcd member 2]  ←── PVC 2 (Azure Disk)
                    ↕ etcd Raft consensus ↕
```

### 3. Persistence Verification

The demo script:
1. Deploys a StatefulSet inside the vcluster that writes a timestamp to a PVC
2. Force-deletes all vcluster control plane pods (simulates restart)
3. Reconnects after pods recover and reads the PVC — the data is still there

This demonstrates two layers of persistence:
- **etcd layer**: Kubernetes resource definitions (StatefulSet, PVC bindings) survive because they were stored in etcd on durable PVCs
- **Application layer**: App data on the PVC survives because PVC bindings in etcd were preserved

---

## etcd Health Checks

Once the vcluster is running, you can run etcd health checks from inside the control plane pod:

```bash
# Check cluster health (all 3 members)
kubectl exec -n vc-etcd etcd-demo-0 --container syncer -- sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://localhost:2379 \
    --cacert=/data/server/tls/etcd/ca.crt \
    --cert=/data/server/tls/etcd/server.crt \
    --key=/data/server/tls/etcd/server.key \
    endpoint health --cluster
'

# List etcd members
kubectl exec -n vc-etcd etcd-demo-0 --container syncer -- sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://localhost:2379 \
    --cacert=/data/server/tls/etcd/ca.crt \
    --cert=/data/server/tls/etcd/server.crt \
    --key=/data/server/tls/etcd/server.key \
    member list -w table
'

# Check etcd endpoint status (leader election info)
kubectl exec -n vc-etcd etcd-demo-0 --container syncer -- sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://localhost:2379 \
    --cacert=/data/server/tls/etcd/ca.crt \
    --cert=/data/server/tls/etcd/server.crt \
    --key=/data/server/tls/etcd/server.key \
    endpoint status --cluster -w table
'
```

> **Note**: The `--container syncer` flag targets the syncer container which bundles etcdctl.
> If it's not available, exec into the `vcluster` container instead.

---

## When to Use etcd vs SQLite

### Use SQLite (default) when:
- Running ephemeral CI/CD pipelines
- Developer preview environments (deleted after a few hours)
- Low resource environments (limited memory/storage)
- Single developer workflows

### Use embedded etcd when:
- Running shared team environments that must stay up
- Testing workloads that require persistent state between sessions
- Simulating production-like HA Kubernetes clusters
- Running vcluster for days/weeks (not hours)
- You need to practice etcd snapshot/restore workflows

---

## Cleanup

```bash
./cleanup-etcd.sh
```

This removes:
- The vcluster (`vcluster delete`)
- All PVCs (etcd data volumes on Azure Disk)
- The host namespace `vc-etcd`
- The kubeconfig context for this vcluster

---

## Further Reading

| Resource | Link |
|----------|------|
| vcluster backing store docs | https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/control-plane/backing-store |
| vcluster HA configuration | https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/control-plane/other/high-availability |
| etcd operations guide | https://etcd.io/docs/v3.5/op-guide/ |
| etcd Raft consensus | https://raft.github.io/ |
| etcd snapshot & restore | https://etcd.io/docs/v3.5/op-guide/recovery/ |
| vcluster persistence docs | https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/control-plane/other/persistence |
