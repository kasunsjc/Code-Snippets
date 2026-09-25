# Rendered by deploy.sh via envsubst. Placeholder: ${BOOKINFO_FQDN}
#
# Routes external traffic arriving on the Gateway above to the productpage
# service, exposing the bookinfo sample app through the Istio ingress gateway's
# public Azure Load Balancer IP under its real Azure DNS hostname.
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bookinfo
  namespace: default
spec:
  hosts:
    - "${BOOKINFO_FQDN}"
  gateways:
    - bookinfo-gateway
  http:
    - match:
        - uri:
            exact: /productpage
        - uri:
            prefix: /static
        - uri:
            exact: /login
        - uri:
            exact: /logout
        - uri:
            prefix: /api/v1/products
      route:
        - destination:
            host: productpage
            port:
              number: 9080
