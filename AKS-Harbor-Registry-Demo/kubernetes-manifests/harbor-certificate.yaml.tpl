# Rendered by deploy.sh via envsubst.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: harbor-tls
  namespace: harbor
spec:
  secretName: harbor-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - ${HARBOR_FQDN}
  usages:
    - digital signature
    - key encipherment
