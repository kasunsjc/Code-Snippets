# DNS Configuration for ArgoCD

## Overview

This demo uses the domain `argo-demo.kasunrajapakse.xyz` to access ArgoCD through Traefik ingress with automatic TLS certificates from Let's Encrypt.

## DNS Setup

### 1. Get the Traefik LoadBalancer IP

After deployment, get the external IP of Traefik:

```bash
kubectl get svc traefik -n traefik
```

Look for the `EXTERNAL-IP` column. For example:
```
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)
traefik   LoadBalancer   10.0.123.45    20.123.45.67     80:30080/TCP,443:30443/TCP
```

### 2. Configure DNS Record

Create an A record in your DNS provider:

**Azure DNS Example:**
```bash
# If using Azure DNS
az network dns record-set a add-record \
  --resource-group <your-dns-zone-rg> \
  --zone-name kasunrajapakse.xyz \
  --record-set-name argo-demo \
  --ipv4-address <TRAEFIK-EXTERNAL-IP>
```

**Manual Configuration:**
- **Type:** A
- **Name:** argo-demo
- **Value:** `<TRAEFIK-EXTERNAL-IP>`
- **TTL:** 300 (5 minutes)

### 3. Verify DNS Resolution

Wait a few minutes for DNS propagation, then verify:

```bash
# Using dig
dig argo-demo.kasunrajapakse.xyz +short

# Using nslookup
nslookup argo-demo.kasunrajapakse.xyz

# Using host
host argo-demo.kasunrajapakse.xyz
```

The command should return the Traefik LoadBalancer IP.

## TLS Certificate

### Automatic Certificate Issuance

Traefik is configured to automatically request a TLS certificate from Let's Encrypt for `argo-demo.kasunrajapakse.xyz`.

### Check Certificate Status

```bash
# Check if certificate was issued successfully
kubectl get certificate -n argocd

# View certificate details
kubectl describe certificate argocd-tls -n argocd

# Check cert-manager logs if there are issues
kubectl logs -n cert-manager deployment/cert-manager -f
```

### Certificate Troubleshooting

If the certificate is not issued:

1. **Verify DNS is resolving correctly:**
   ```bash
   curl -v http://argo-demo.kasunrajapakse.xyz
   ```

2. **Check cert-manager challenges:**
   ```bash
   kubectl get challenges -n argocd
   kubectl describe challenges -n argocd
   ```

3. **Check Let's Encrypt rate limits:**
   - Let's Encrypt has rate limits (50 certificates per domain per week)
   - Use the staging issuer for testing: `letsencrypt-staging`

4. **Switch to staging issuer for testing:**
   Edit `manifests/argocd-ingress.yaml` and change:
   ```yaml
   tls:
     certResolver: letsencrypt  # Change to letsencrypt-staging for testing
   ```

## Access ArgoCD

Once DNS is configured and certificate is issued:

```bash
# Access ArgoCD in browser
https://argo-demo.kasunrajapakse.xyz
```

You should see:
- A valid TLS certificate (green padlock in browser)
- ArgoCD login page
- No certificate warnings

## Alternative: Using Hosts File (Local Testing)

For local testing without DNS:

1. **Edit your hosts file:**
   ```bash
   # macOS/Linux
   sudo nano /etc/hosts
   
   # Windows (as Administrator)
   notepad C:\Windows\System32\drivers\etc\hosts
   ```

2. **Add entry:**
   ```
   <TRAEFIK-EXTERNAL-IP>  argo-demo.kasunrajapakse.xyz
   ```

3. **Access ArgoCD:**
   ```
   https://argo-demo.kasunrajapakse.xyz
   ```

   **Note:** You'll get a certificate warning because Let's Encrypt can't verify the domain through HTTP challenge when using hosts file.

## Monitoring

### View Traefik Dashboard

```bash
# Port forward to Traefik dashboard
kubectl port-forward -n traefik svc/traefik 9000:9000

# Access dashboard
http://localhost:9000/dashboard/
```

### Check Ingress Routes

```bash
# List all IngressRoutes
kubectl get ingressroute -A

# Describe ArgoCD IngressRoute
kubectl describe ingressroute argocd-server -n argocd
```

## Troubleshooting

### Connection Timeout

If you can't connect:
1. Verify DNS is resolving to correct IP
2. Check NSG/firewall rules allow traffic to LoadBalancer
3. Verify Traefik pods are running:
   ```bash
   kubectl get pods -n traefik
   ```

### Certificate Not Issued

1. Check ClusterIssuer is ready:
   ```bash
   kubectl get clusterissuer
   ```

2. View cert-manager logs:
   ```bash
   kubectl logs -n cert-manager deployment/cert-manager
   ```

3. Check HTTP-01 challenge:
   ```bash
   kubectl get challenges -A
   kubectl describe challenge <challenge-name> -n argocd
   ```

### 502 Bad Gateway

If you get 502 errors:
1. Check ArgoCD server pods are running:
   ```bash
   kubectl get pods -n argocd
   ```

2. Check ArgoCD server logs:
   ```bash
   kubectl logs -n argocd deployment/argocd-server
   ```

3. Verify service endpoints:
   ```bash
   kubectl get endpoints argocd-server -n argocd
   ```
