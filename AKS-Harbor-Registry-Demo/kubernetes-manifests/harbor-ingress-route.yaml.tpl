# Rendered by deploy.sh via envsubst.
# Harbor keeps HTTP internally; Traefik terminates TLS using harbor-tls.
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: harbor-portal
  namespace: harbor
  labels:
    app.kubernetes.io/name: harbor
    app.kubernetes.io/component: portal
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`${HARBOR_FQDN}`)
      kind: Rule
      services:
        - name: harbor
          port: 80
      middlewares:
        - name: harbor-headers
  tls:
    secretName: harbor-tls
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: harbor-http
  namespace: harbor
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`${HARBOR_FQDN}`)
      kind: Rule
      middlewares:
        - name: redirect-to-https
      services:
        - name: harbor
          port: 80
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: harbor-headers
  namespace: harbor
spec:
  headers:
    sslRedirect: true
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true
    forceSTSHeader: true
    customRequestHeaders:
      X-Forwarded-Proto: "https"
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-to-https
  namespace: harbor
spec:
  redirectScheme:
    scheme: https
    permanent: true
