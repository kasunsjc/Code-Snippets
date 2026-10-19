apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: k6-letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: k6-letsencrypt-prod-account-key
    solvers:
      - dns01:
          azureDNS:
            subscriptionID: ${SUBSCRIPTION_ID}
            resourceGroupName: ${DNS_ZONE_RESOURCE_GROUP}
            hostedZoneName: ${DNS_ZONE_NAME}
            environment: AzurePublicCloud
            managedIdentity:
              clientID: ${CERT_MANAGER_CLIENT_ID}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: httpbin-tls
  namespace: k6-demo
spec:
  secretName: httpbin-tls
  dnsNames:
    - ${HTTPBIN_FQDN}
  issuerRef:
    name: k6-letsencrypt-prod
    kind: ClusterIssuer
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin
  namespace: k6-demo
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - ${HTTPBIN_FQDN}
      secretName: httpbin-tls
  rules:
    - host: ${HTTPBIN_FQDN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: target-app
                port:
                  number: 80