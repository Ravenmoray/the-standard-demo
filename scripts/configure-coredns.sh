#!/usr/bin/env bash
# Configure CoreDNS for demo.internal internal domain resolution
#
# This script patches the CoreDNS ConfigMap in kube-system to add a
# forward/hosts stanza for the demo.internal domain. This is required for:
#   1. Workloads in the cluster to resolve app.demo.internal
#   2. cert-manager's ACME HTTP-01 self-check to resolve the hostname
#      being validated (Lesson 3.1 from oracle-k8 gap analysis)
#
# MUST be run AFTER ingress-nginx is deployed and has a LoadBalancer IP.
#
# Usage:
#   ./scripts/configure-coredns.sh [INGRESS_IP]
#   # If INGRESS_IP is not provided, script will auto-detect from ingress-nginx service.

set -euo pipefail

INGRESS_IP="${1:-}"
INGRESS_NAMESPACE="ingress-nginx"
INGRESS_SVC="ingress-nginx-controller"

echo "[configure-coredns] Configuring CoreDNS for demo.internal..."

# Auto-detect ingress IP if not provided
if [[ -z "${INGRESS_IP}" ]]; then
  echo "[configure-coredns] Auto-detecting ingress-nginx LoadBalancer IP..."
  INGRESS_IP="$(kubectl get svc "${INGRESS_SVC}" \
    --namespace "${INGRESS_NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

  if [[ -z "${INGRESS_IP}" ]]; then
    echo "ERROR: Could not detect ingress-nginx LoadBalancer IP."
    echo "       Ensure ingress-nginx is deployed and has a LoadBalancer IP assigned."
    echo "       Or pass the IP as an argument: $0 <INGRESS_IP>"
    exit 1
  fi
fi

echo "[configure-coredns] Using ingress IP: ${INGRESS_IP}"
echo "[configure-coredns] app.demo.internal -> ${INGRESS_IP}"

# Build the patched Corefile
COREFILE=".:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}

demo.internal:53 {
    errors
    cache 30
    hosts {
        ${INGRESS_IP} app.demo.internal
        fallthrough
    }
}"

# Apply the patch
kubectl patch configmap coredns \
  --namespace kube-system \
  --type merge \
  -p "{\"data\":{\"Corefile\":$(echo "${COREFILE}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}}"

echo "[configure-coredns] CoreDNS ConfigMap updated."

# Restart CoreDNS to pick up the change
echo "[configure-coredns] Restarting CoreDNS pods..."
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

echo "[configure-coredns] Verifying DNS resolution..."
# Test from within the cluster using a temporary pod
kubectl run dns-test \
  --image=docker.io/library/busybox:1.36 \
  --restart=Never \
  --rm \
  --timeout=30s \
  -it \
  -- nslookup app.demo.internal 2>/dev/null || true

echo ""
echo "[configure-coredns] CoreDNS configuration complete."
echo "  app.demo.internal resolves to: ${INGRESS_IP}"
