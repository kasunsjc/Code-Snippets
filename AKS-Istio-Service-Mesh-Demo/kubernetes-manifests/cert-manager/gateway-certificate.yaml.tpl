# Rendered by deploy.sh via envsubst. Placeholder: ${BOOKINFO_FQDN}
#
# IMPORTANT: this Certificate's Secret must live in the `aks-istio-ingress`
# namespace - not the Gateway resource's own namespace. The AKS-managed
# ingress gateway pods run there and only read TLS secrets (via SDS) from
# their own pod namespace, regardless of which namespace the Gateway CR
# itself is created in.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: bookinfo-gateway-tls
  namespace: aks-istio-ingress
spec:
  secretName: bookinfo-gateway-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - ${BOOKINFO_FQDN}
  usages:
    - digital signature
    - key encipherment
