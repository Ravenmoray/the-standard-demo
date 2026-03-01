#!/usr/bin/env bash
# PKI Bootstrap Script
# Generates the step-ca root CA and intermediate CA, then creates the
# necessary K8s Secrets and ConfigMaps for step-ca to operate.
#
# Prerequisites:
#   - step CLI installed: https://smallstep.com/docs/step-cli/installation/
#   - kubectl configured and pointing at the target cluster
#   - step-ca namespace exists (apply k8s/base/step-ca/namespace.yaml first)
#
# Usage:
#   ./scripts/bootstrap-pki.sh
#
# The root CA private key (root_ca.key) is generated locally and should be
# moved to offline storage (e.g., encrypted USB, HSM) after bootstrapping.
# Only the root CA certificate (root_ca.crt) is kept online in K8s.
#
# The intermediate CA key (intermediate_ca.key) stays online in the
# step-ca-secrets K8s Secret, mounted into the step-ca pod.
#
# Run this script exactly ONCE. Re-running will generate a new CA chain,
# which will invalidate all existing certificates issued by the old chain.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKI_DIR="${PROJECT_ROOT}/.pki"
NAMESPACE="step-ca"

# CA configuration
ROOT_CA_NAME="Demo Corp Root CA"
INTERMEDIATE_CA_NAME="Demo Corp Intermediate CA"
DOMAIN="demo.internal"
# Root CA: 10-year validity (offline root, long-lived is acceptable)
ROOT_DURATION="87600h"
# Intermediate CA: 5-year validity
INTERMEDIATE_DURATION="43800h"

echo "[bootstrap-pki] Starting PKI bootstrap for domain: ${DOMAIN}"
echo "[bootstrap-pki] PKI material will be generated in: ${PKI_DIR}"
echo ""

# Verify prerequisites
if ! command -v step &>/dev/null; then
  echo "ERROR: 'step' CLI not found. Install from: https://smallstep.com/docs/step-cli/"
  exit 1
fi

if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "ERROR: Namespace '${NAMESPACE}' not found. Apply k8s/base/step-ca/namespace.yaml first."
  exit 1
fi

# Check if secret already exists (prevent accidental re-bootstrap)
if kubectl get secret step-ca-secrets -n "${NAMESPACE}" &>/dev/null; then
  echo "ERROR: Secret 'step-ca-secrets' already exists in namespace '${NAMESPACE}'."
  echo "       Re-running bootstrap will invalidate all existing certificates."
  echo "       If you truly need to re-bootstrap, delete the secret first:"
  echo "         kubectl delete secret step-ca-secrets -n ${NAMESPACE}"
  exit 1
fi

# Create PKI working directory (excluded from git via .gitignore)
mkdir -p "${PKI_DIR}"
chmod 700 "${PKI_DIR}"

echo "[bootstrap-pki] Generating root CA..."
step certificate create \
  "${ROOT_CA_NAME}" \
  "${PKI_DIR}/root_ca.crt" \
  "${PKI_DIR}/root_ca.key" \
  --profile root-ca \
  --no-password \
  --insecure \
  --not-after "${ROOT_DURATION}" \
  --kty EC \
  --crv P-256 \
  --san "${DOMAIN}" \
  --force

echo "[bootstrap-pki] Generating intermediate CA..."
step certificate create \
  "${INTERMEDIATE_CA_NAME}" \
  "${PKI_DIR}/intermediate_ca.crt" \
  "${PKI_DIR}/intermediate_ca.key" \
  --profile intermediate-ca \
  --ca "${PKI_DIR}/root_ca.crt" \
  --ca-key "${PKI_DIR}/root_ca.key" \
  --no-password \
  --insecure \
  --not-after "${INTERMEDIATE_DURATION}" \
  --kty EC \
  --crv P-256 \
  --force

echo "[bootstrap-pki] Verifying CA chain..."
step certificate verify \
  "${PKI_DIR}/intermediate_ca.crt" \
  --roots "${PKI_DIR}/root_ca.crt"
echo "[bootstrap-pki] CA chain verification: PASSED"

echo "[bootstrap-pki] Creating step-ca-secrets Kubernetes Secret..."
kubectl create secret generic step-ca-secrets \
  --namespace "${NAMESPACE}" \
  --from-file=root_ca.crt="${PKI_DIR}/root_ca.crt" \
  --from-file=intermediate_ca.crt="${PKI_DIR}/intermediate_ca.crt" \
  --from-file=intermediate_ca.key="${PKI_DIR}/intermediate_ca.key"

echo "[bootstrap-pki] Updating step-ca-root-cert ConfigMap with root CA certificate..."
ROOT_CA_CONTENT="$(cat "${PKI_DIR}/root_ca.crt")"
kubectl patch configmap step-ca-root-cert \
  --namespace "${NAMESPACE}" \
  --type merge \
  -p "{\"data\":{\"root_ca.crt\":\"${ROOT_CA_CONTENT}\"}}"

echo ""
echo "[bootstrap-pki] PKI bootstrap complete."
echo ""
echo "NEXT STEPS:"
echo "  1. Copy root CA cert for workstation trust:"
echo "     ${PKI_DIR}/root_ca.crt"
echo "     -> Place in ansible/roles/workstation/files/demo-corp-root-ca.crt"
echo ""
echo "  2. Move the root CA key to offline storage:"
echo "     ${PKI_DIR}/root_ca.key"
echo "     -> This key must NOT remain on the admin workstation long-term."
echo "     -> Store in an encrypted offline location (hardware key, encrypted USB)."
echo ""
echo "  3. Update the ClusterIssuer caBundle in k8s/base/cert-manager/cluster-issuer.yaml:"
echo "     BUNDLE=\$(kubectl get configmap step-ca-root-cert -n step-ca \\"
echo "       -o jsonpath='{.data.root_ca\\.crt}' | base64 -w0)"
echo "     Then paste the value into the caBundle field."
echo ""
echo "  4. Apply step-ca deployment:"
echo "     kubectl apply -k k8s/base/step-ca/"
echo ""
echo "  5. Wait for step-ca to become ready:"
echo "     kubectl wait --for=condition=available deployment/step-ca -n step-ca --timeout=120s"
echo ""
echo "  6. Apply cert-manager cluster issuer:"
echo "     kubectl apply -f k8s/base/cert-manager/cluster-issuer.yaml"
echo ""

# Emit a reminder about the root key
echo "WARNING: The root CA private key is at: ${PKI_DIR}/root_ca.key"
echo "         Move it to offline storage before this session ends."
