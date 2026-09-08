# Rendered by deploy.sh via `envsubst` before `helm upgrade --install harbor`.
# Placeholders: ${HARBOR_FQDN}
#
# This is a "basic" Harbor install: bundled/internal database, redis and
# trivy (no external Postgres/Redis/object storage), persistence on the AKS
# default storage class (managed-csi).
expose:
  type: ingress
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-tls
  ingress:
    hosts:
      core: ${HARBOR_FQDN}
    className: traefik
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod

externalURL: https://${HARBOR_FQDN}

persistence:
  enabled: true
  resourcePolicy: "keep"

# Azure Monitor managed Prometheus scrapes Harbor via its own ServiceMonitor
# (harbor-azure-monitor-servicemonitor.yaml, azmonitoring.coreos.com/v1).
# Keep the chart's own ServiceMonitor disabled - it uses the OSS
# monitoring.coreos.com/v1 API group, which Azure Monitor does not watch.
metrics:
  enabled: true
  serviceMonitor:
    enabled: false

core:
  # CONFIG_OVERWRITE_JSON caveat: once this is set, ALL Harbor user-scope
  # settings (including auth_mode) become read-only in the Harbor UI - any
  # further change (e.g. enabling OIDC below) must be made here and applied
  # with `helm upgrade`, not through Administration -> Configuration.
  configureUserSettings: |
    {
      "audit_log_forward_endpoint": "harbor-audit-forwarder.harbor.svc.cluster.local:10514",
      "skip_audit_log_database": false
    }
  # Future demo placeholder (Azure AD / Entra ID OIDC SSO for Harbor) - add these
  # keys to the JSON block above and re-run `helm upgrade` to enable it, do not
  # uncomment as-is:
  #   "auth_mode": "oidc_auth",
  #   "oidc_name": "entra-id",
  #   "oidc_endpoint": "https://login.microsoftonline.com/<tenant-id>/v2.0",
  #   "oidc_client_id": "<entra-app-client-id>",
  #   "oidc_client_secret": "<entra-app-client-secret>",
  #   "oidc_scope": "openid,profile,email",
  #   "oidc_verify_cert": true,
  #   "oidc_auto_onboard": true,
  #   "oidc_user_claim": "preferred_username"
  # Harbor's local `admin` account always stays DB-authenticated, so it
  # remains a break-glass login after OIDC is enabled.
