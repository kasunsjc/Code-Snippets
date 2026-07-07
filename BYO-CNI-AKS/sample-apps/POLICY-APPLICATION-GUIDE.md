# Cilium Network Policy Application Guide

## Current Issue

The **database is accessible from frontend** because only the L7 policy for backend-api is applied, but the database policy is missing.

## Expected Network Topology

```
Frontend → Backend-API → Database
   ✓          ✓            ✓
   
Frontend → Database
         ✗ BLOCKED
```

## Policy Application Order

### 1. Basic L3/L4 Policies (Recommended First)

Apply these policies to establish basic network segmentation:

```bash
# Allow frontend -> backend-api traffic only
kubectl apply -f 02-cilium-l3-l4-policy.yaml

# Allow backend-api -> database traffic only (BLOCKS frontend -> database)
kubectl apply -f 03-cilium-database-policy.yaml
```

### 2. Advanced L7 Policy (Optional Replacement)

**Note:** The L7 policy requires specific HTTP paths to exist on the backend. For demo nginx pods, this will cause 404 errors.

```bash
# L7 HTTP-aware policy (replaces 02-cilium-l3-l4-policy.yaml)
# Only use this if your backend-api has actual /api/* and /health endpoints
kubectl apply -f 04-cilium-l7-policy.yaml
```

### 3. Additional Policies (Optional)

```bash
# Cluster-wide default deny ingress
kubectl apply -f 05-cilium-clusterwide-policy.yaml

# DNS-aware egress policy
kubectl apply -f 06-cilium-dns-egress-policy.yaml
```

## Quick Fix for Your Current Issue

To fix the frontend -> database access issue:

```bash
# Remove the L7 policy (it's causing 404 errors with demo nginx)
kubectl delete -f 04-cilium-l7-policy.yaml

# Apply the basic L3/L4 policies
kubectl apply -f 02-cilium-l3-l4-policy.yaml
kubectl apply -f 03-cilium-database-policy.yaml
```

## Verify Policies

```bash
# Check applied policies
kubectl get ciliumnetworkpolicies -n cilium-demo

# Run the test script
./test-policies.sh
```

## Expected Test Results

- ✓ Frontend → Backend-API: **ALLOWED**
- ✗ Frontend → Database: **BLOCKED** by policy
- ✓ Backend-API → Database: **ALLOWED**

## Policy Descriptions

| File | Purpose | Blocks |
|------|---------|--------|
| `02-cilium-l3-l4-policy.yaml` | Controls access to backend-api | Only allows frontend → backend-api |
| `03-cilium-database-policy.yaml` | Controls access to database | Only allows backend-api → database |
| `04-cilium-l7-policy.yaml` | HTTP method/path filtering | L7 rules for specific API paths |
| `05-cilium-clusterwide-policy.yaml` | Default deny ingress | Blocks all ingress by default |
| `06-cilium-dns-egress-policy.yaml` | DNS egress control | Controls DNS queries |
