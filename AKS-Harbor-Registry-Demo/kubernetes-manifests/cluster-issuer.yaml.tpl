# Rendered by deploy.sh via `envsubst` before kubectl apply. Placeholders:
#   ${SUBSCRIPTION_ID}, ${DNS_ZONE_RESOURCE_GROUP}, ${DNS_ZONE_NAME},
#   ${CERT_MANAGER_CLIENT_ID}, ${ACME_EMAIL}
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          azureDNS:
            subscriptionID: ${SUBSCRIPTION_ID}
            resourceGroupName: ${DNS_ZONE_RESOURCE_GROUP}
            hostedZoneName: ${DNS_ZONE_NAME}
            environment: AzurePublicCloud
          managedIdentity:
            clientID: ${CERT_MANAGER_CLIENT_ID}
