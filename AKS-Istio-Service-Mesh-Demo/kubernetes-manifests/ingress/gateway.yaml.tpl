# Rendered by deploy.sh via envsubst. Placeholder: ${BOOKINFO_FQDN}
#
# Istio Gateway (networking.istio.io) bound to the AKS-managed external
# ingress gateway deployment/service `aks-istio-ingressgateway-external` in
# the aks-istio-ingress namespace. This is NOT the Kubernetes Gateway API used
# by the separate "AKS App Routing (Istio)" add-on - see the root README for
# the distinction between the two.
#
# Port 80 redirects to HTTPS; port 443 terminates TLS using the certificate
# cert-manager issues into the aks-istio-ingress namespace (see
# kubernetes-manifests/cert-manager/gateway-certificate.yaml.tpl).
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: bookinfo-gateway
  namespace: default
spec:
  selector:
    istio: aks-istio-ingressgateway-external
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "${BOOKINFO_FQDN}"
      tls:
        httpsRedirect: true
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "${BOOKINFO_FQDN}"
      tls:
        mode: SIMPLE
        credentialName: bookinfo-gateway-tls
