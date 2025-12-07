# Sample Applications for Troubleshooting

This directory contains Kubernetes applications with intentional issues to demonstrate the Agentic CLI's troubleshooting capabilities.

## Applications Overview

### 1. CrashLoop App
**Issue**: Application crashes repeatedly due to missing environment variables
- **File**: `crashloop-app.yaml`
- **Problem**: Pod enters CrashLoopBackOff state
- **Use Case**: Debugging container startup failures

### 2. OOMKilled App
**Issue**: Application exceeds memory limits and gets killed
- **File**: `oomkilled-app.yaml`
- **Problem**: Out of Memory errors
- **Use Case**: Resource limit troubleshooting

### 3. ImagePull Error
**Issue**: Invalid container image reference
- **File**: `imagepull-error.yaml`
- **Problem**: ImagePullBackOff / ErrImagePull
- **Use Case**: Image registry and authentication issues

### 4. Pending Pod
**Issue**: Pod cannot be scheduled due to resource constraints
- **File**: `pending-pod.yaml`
- **Problem**: Pod stuck in Pending state
- **Use Case**: Node resource and scheduling problems

### 5. Liveness Probe Failure
**Issue**: Health check fails causing constant restarts
- **File**: `liveness-failure.yaml`
- **Problem**: Failing liveness probe
- **Use Case**: Health check configuration issues

### 6. Network Policy Block
**Issue**: Service cannot communicate due to network policies
- **File**: `network-policy-block.yaml`
- **Problem**: Connection timeouts
- **Use Case**: Network connectivity troubleshooting

### 7. ConfigMap Missing
**Issue**: Application references non-existent ConfigMap
- **File**: `configmap-missing.yaml`
- **Problem**: CreateContainerConfigError
- **Use Case**: Configuration dependency issues

### 8. Init Container Failure
**Issue**: Init container fails preventing main container startup
- **File**: `init-container-failure.yaml`
- **Problem**: Init:Error or Init:CrashLoopBackOff
- **Use Case**: Initialization sequence problems

## Quick Start

### Deploy All Applications
```bash
kubectl apply -f sample-apps/
```

### Deploy Individual Apps
```bash
kubectl apply -f sample-apps/crashloop-app.yaml
```

### Troubleshoot with Agentic CLI

Once deployed, use the agent to investigate:

```bash
# General cluster health
az aks agent "What issues are in my cluster?"

# Specific application
az aks agent "Why is the crashloop-app pod failing?"

# Resource investigation
az aks agent "Which pods are consuming too much memory?"

# Network debugging
az aks agent "Why can't frontend-app reach backend-service?"
```

## Cleanup

Remove all sample applications:
```bash
kubectl delete namespace troubleshooting-demos
```

Or remove individual apps:
```bash
kubectl delete -f sample-apps/crashloop-app.yaml
```
