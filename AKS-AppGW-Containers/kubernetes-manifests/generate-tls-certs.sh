#!/usr/bin/env bash
# Generate self-signed TLS certificates for AGFC demo scenarios
# - SSL Offloading: creates listener-tls-secret
# - Backend mTLS: creates frontend.com, backend.com, gateway-client-cert, ca.bundle
#
# Usage: ./generate-tls-certs.sh [ssl-offloading|backend-mtls|all]
# Default: all
set -euo pipefail

NAMESPACE="test-infra"
CERT_DIR="$(mktemp -d)"
SCENARIO="${1:-all}"

echo "=== Generating TLS certificates in $CERT_DIR ==="

# ----- Helper -----
generate_ca() {
    echo "--- Creating Certificate Authority ---"
    openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/ca.key"
    openssl req -new -x509 -sha256 -key "$CERT_DIR/ca.key" \
        -subj "/O=AGFC Demo/CN=AGFC Demo CA" \
        -days 365 -out "$CERT_DIR/ca.crt"
}

generate_cert() {
    local name="$1" cn="$2"
    echo "--- Generating certificate for $cn ---"
    openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/${name}.key"
    openssl req -new -sha256 -key "$CERT_DIR/${name}.key" \
        -subj "/O=AGFC Demo/CN=${cn}" \
        -out "$CERT_DIR/${name}.csr"
    openssl x509 -req -sha256 -in "$CERT_DIR/${name}.csr" \
        -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
        -days 365 -out "$CERT_DIR/${name}.crt" \
        -extfile <(printf "subjectAltName=DNS:%s" "$cn")
}

# ----- SSL Offloading certs -----
create_ssl_offloading_secret() {
    echo ""
    echo "=== SSL Offloading — listener-tls-secret ==="
    openssl ecparam -name prime256v1 -genkey -noout -out "$CERT_DIR/listener.key"
    openssl req -new -x509 -sha256 -key "$CERT_DIR/listener.key" \
        -subj "/O=AGFC Demo/CN=agfc-demo.example.com" \
        -days 365 -out "$CERT_DIR/listener.crt"

    kubectl create secret tls listener-tls-secret \
        --cert="$CERT_DIR/listener.crt" \
        --key="$CERT_DIR/listener.key" \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "  ✓ listener-tls-secret created"
}

# ----- Backend mTLS certs -----
create_backend_mtls_secrets() {
    echo ""
    echo "=== Backend mTLS — CA, server, client, and frontend certs ==="
    generate_ca

    # Frontend cert (for the Gateway HTTPS listener)
    generate_cert "frontend" "frontend.com"

    # Backend cert (server cert for the mTLS nginx backend)
    generate_cert "backend" "backend.com"

    # Gateway client cert (presented by AGFC to the backend)
    generate_cert "gateway-client" "gateway.agfc.example.com"

    # Create Kubernetes secrets
    kubectl create secret tls frontend.com \
        --cert="$CERT_DIR/frontend.crt" \
        --key="$CERT_DIR/frontend.key" \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "  ✓ frontend.com secret created"

    kubectl create secret tls backend.com \
        --cert="$CERT_DIR/backend.crt" \
        --key="$CERT_DIR/backend.key" \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "  ✓ backend.com secret created"

    kubectl create secret tls gateway-client-cert \
        --cert="$CERT_DIR/gateway-client.crt" \
        --key="$CERT_DIR/gateway-client.key" \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "  ✓ gateway-client-cert secret created"

    kubectl create secret generic ca.bundle \
        --from-file=ca.crt="$CERT_DIR/ca.crt" \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo "  ✓ ca.bundle secret created"
}

# ----- Main -----
case "$SCENARIO" in
    ssl-offloading)
        create_ssl_offloading_secret
        ;;
    backend-mtls)
        create_backend_mtls_secrets
        ;;
    all)
        create_ssl_offloading_secret
        create_backend_mtls_secrets
        ;;
    *)
        echo "Usage: $0 [ssl-offloading|backend-mtls|all]"
        exit 1
        ;;
esac

echo ""
echo "=== Done — cleaning up temp files ==="
rm -rf "$CERT_DIR"
echo "Certificates created successfully in namespace $NAMESPACE"
