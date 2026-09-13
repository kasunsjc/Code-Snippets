apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: harbor-secrets
  namespace: harbor
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    userAssignedIdentityID: "${KV_CSI_CLIENT_ID}"
    keyvaultName: "${KEY_VAULT_NAME}"
    tenantId: "${TENANT_ID}"
    objects: |
      array:
        - objectName: harbor-admin-password
          objectType: secret
          secretName: harbor-admin
          secretVersion: ""
        - objectName: harbor-secret-key
          objectType: secret
          secretName: harbor-secretkey
          secretVersion: ""
        - objectName: harbor-postgres-password
          objectType: secret
          secretName: harbor-database
          secretVersion: ""
        - objectName: harbor-redis-key
          objectType: secret
          secretName: harbor-redis
          secretVersion: ""
  secretObjects:
    - secretName: harbor-admin
      type: Opaque
      data:
        - objectName: harbor-admin-password
          key: HARBOR_ADMIN_PASSWORD
    - secretName: harbor-secretkey
      type: Opaque
      data:
        - objectName: harbor-secret-key
          key: secretKey
    - secretName: harbor-database
      type: Opaque
      data:
        - objectName: harbor-postgres-password
          key: password
    - secretName: harbor-redis
      type: Opaque
      data:
        - objectName: harbor-redis-key
          key: REDIS_PASSWORD
