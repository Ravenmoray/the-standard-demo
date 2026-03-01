# Deployment Runbook

Step-by-step deployment following The Standard's non-negotiable ordering.

## Prerequisites

- [ ] OCI account active with trial credits in us-chicago-1
- [ ] OCI CLI installed and configured (`oci setup config`)
- [ ] OpenTofu >= 1.6.0 installed
- [ ] Ansible >= 2.15 installed with `ansible.posix` and `ansible.utils` collections
- [ ] `step` CLI installed (for PKI bootstrap)
- [ ] `helm` >= 3.12 installed
- [ ] `kubectl` installed
- [ ] SSH key pair generated for OCI VM access
- [ ] Gitleaks pre-commit hook installed

## Layer 1: Remote State Bootstrap

```bash
# Get your OCI Object Storage namespace
export NAMESPACE=$(oci os ns get --query 'data' --raw-output)
export COMPARTMENT_ID="<your-compartment-ocid>"

# Create state bucket
oci os bucket create \
  --compartment-id "$COMPARTMENT_ID" \
  --namespace "$NAMESPACE" \
  --name "it101-poc-tofu-state" \
  --versioning Enabled \
  --public-access-type NoPublicAccess

# Create S3-compatible access key
oci iam customer-secret-key create \
  --user-id <USER_OCID> \
  --display-name "opentofu-state-key"
# Save both keys immediately — secret is shown only once
```

## Layer 2: Network Provisioning

```bash
cd infra/tofu/environments/poc

# Copy and fill in variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI details

# Initialize with remote state
tofu init -backend-config=.s3.tfbackend

# Review and apply
tofu plan
tofu apply
```

**Verify:** All subnets created, object storage buckets exist.

## Layer 3: Compute Provisioning

Compute is in the same Tofu apply as network (single root module). After apply:

```bash
# Verify SSH to edge nodes (public IPs)
ssh -i ~/.ssh/oci opc@<edge-01-public-ip>

# Verify SSH to private nodes via edge as jump host
ssh -J opc@<edge-01-public-ip> opc@<ctrl-01-private-ip>
```

**Verify:** All 6 VMs running, SSH access works.

## Layer 4: OS Hardening

```bash
cd ansible/

# Update inventory with actual IPs from Tofu outputs
# Edit inventory/hosts.yml

# Verify inventory
ansible-inventory --list

# Run hardening
ansible-playbook playbooks/harden.yml
```

**Verify:**
```bash
# SSH still works (hardened, key-only)
ssh opc@<node-ip>

# Firewalld active
sudo firewall-cmd --list-all

# Fail2ban running
sudo fail2ban-client status sshd
```

## Layer 5: K3s + Cilium Bootstrap

```bash
ansible-playbook playbooks/bootstrap-k3s.yml
```

**Verify:**
```bash
# Get kubeconfig (fetched to ansible/kubeconfig/)
export KUBECONFIG=kubeconfig/it101-ctrl-01.yaml

# All nodes Ready
kubectl get nodes -o wide

# Cilium healthy
cilium status

# Cilium pod count matches node count
kubectl get pods -n kube-system -l k8s-app=cilium
```

## Layer 6: PKI Bootstrap

```bash
# Create step-ca namespace first
kubectl apply -f k8s/base/step-ca/namespace.yaml

# Generate CA chain and create K8s secrets
./scripts/bootstrap-pki.sh

# Copy root CA cert for workstation distribution
cp .pki/root_ca.crt ansible/roles/workstation/files/demo-corp-root-ca.crt

# CRITICAL: Move root CA key to offline storage
# .pki/root_ca.key must NOT remain on workstation long-term
```

## Layer 7: cert-manager + step-ca Deployment

```bash
# Install cert-manager CRDs + controller
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  -f k8s/base/cert-manager/helm-values.yaml

# Apply step-ca deployment
kubectl apply -k k8s/base/step-ca/

# Wait for step-ca to be ready
kubectl wait --for=condition=available deployment/step-ca -n step-ca --timeout=120s

# Update ClusterIssuer caBundle with root CA cert
BUNDLE=$(kubectl get configmap step-ca-root-cert -n step-ca \
  -o jsonpath='{.data.root_ca\.crt}' | base64 -w0)
# Edit k8s/base/cert-manager/cluster-issuer.yaml: set caBundle to $BUNDLE

# Apply ClusterIssuer
kubectl apply -f k8s/base/cert-manager/cluster-issuer.yaml

# Configure CoreDNS for demo.internal resolution
./scripts/configure-coredns.sh
```

**Verify:**
```bash
kubectl get clusterissuer step-ca-acme
# STATUS should be True/Ready
```

## Layer 8: ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f k8s/base/ingress-nginx/helm-values.yaml
```

**Verify:**
```bash
kubectl get svc -n ingress-nginx
# Note the EXTERNAL-IP or CLUSTER-IP for the controller
```

## Layer 9: Demo App Deployment

```bash
# Cross-compile the Go binary for ARM64 (from your local machine)
cd app/
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o demo-app .

# SCP binary and Dockerfile to the control node
scp -J opc@<edge-ip> demo-app Dockerfile opc@<ctrl-ip>:~/

# On the control node: build with buildah and import into K3s
ssh -J opc@<edge-ip> opc@<ctrl-ip>
sudo buildah build -t localhost/demo-app:1.0.0 .
sudo buildah push localhost/demo-app:1.0.0 docker-archive:/tmp/demo-app.tar

# Import image on all K3s nodes (ctrl + workers)
sudo k3s ctr images import /tmp/demo-app.tar
# Repeat on each worker node (SCP the tar, then import)

# Deploy
kubectl apply -k k8s/base/demo-app/

# Wait for certificate to be issued
kubectl get certificate -n demo-app
# STATUS should be True
```

**Verify:**
```bash
# From a cluster node:
curl -k https://app.demo.internal/healthz
# Should return {"status":"ok"}
```

## Layer 10: Workstation Setup

```bash
cd ansible/

# Get ingress IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# If no LoadBalancer (K3s default), use a node's private IP:
INGRESS_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Run workstation setup
ansible-playbook playbooks/setup-workstation.yml \
  -e workstation_ingress_ip=$INGRESS_IP
```

**Verify (the MVP test):**
```bash
# SSH to workstation from your machine (via jump host)
ssh -J opc@<edge-public-ip> opc@<workstation-private-ip>

# On the workstation:
curl -v https://app.demo.internal
# Should return HTTP 200 with NO certificate warning
# The "SSL certificate verify ok" line confirms enterprise CA trust
```

## Verification Summary

| Check | Command | Expected |
|-------|---------|----------|
| K3s nodes healthy | `kubectl get nodes` | All nodes Ready |
| Cilium operational | `cilium status` | OK |
| step-ca running | `kubectl get pods -n step-ca` | Running |
| cert-manager ready | `kubectl get clusterissuer` | Ready=True |
| Demo app running | `kubectl get pods -n demo-app` | Running |
| TLS cert issued | `kubectl get cert -n demo-app` | Ready=True |
| Workstation DHCP | `ip addr show` on workstation | 10.0.100.x address |
| CA trusted | `curl https://app.demo.internal` | HTTP 200, no cert warning |
| SSH access | `ssh opc@<workstation-ip>` | Connects |
