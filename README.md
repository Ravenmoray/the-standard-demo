# The Standard Demo

Production-grade infrastructure on Oracle Cloud, implementing [The Standard](../The_Standard/) IT-101 Phase 1 at minimal scale.

## What This Builds

- **6 VMs** on OCI (us-chicago-1) across isolated security zones
- **K3s cluster** with Cilium eBPF CNI (3 nodes: 1 control, 2 workers)
- **Internal PKI** (step-ca root + intermediate CA, cert-manager ACME)
- **Demo web app** at `https://app.demo.internal` with enterprise TLS
- **Virtual workstation** on a separate DHCP network that trusts the enterprise CA

## Architecture

```
Internet → DMZ (edge nodes) → APP (K3s + Cilium) → demo-app
                                    ↓
                              step-ca → cert-manager → TLS certs

WORKSTATION subnet (10.0.100.0/24, DHCP)
  └── curl https://app.demo.internal → HTTP 200, no cert warning
```

See [docs/architecture.md](docs/architecture.md) for the full network diagram and design decisions.

## Prerequisites

- OCI account with trial credits (us-chicago-1)
- OpenTofu >= 1.6.0, Ansible >= 2.15, Helm >= 3.12, kubectl, step CLI
- SSH key pair for VM access

## Quick Start

See [docs/deployment-runbook.md](docs/deployment-runbook.md) for the full step-by-step guide.

```bash
# 1. Infrastructure
cd infra/tofu/environments/poc
cp terraform.tfvars.example terraform.tfvars  # fill in your values
tofu init -backend-config=.s3.tfbackend
tofu apply

# 2. OS hardening + K3s
cd ../../../../ansible
ansible-playbook playbooks/harden.yml
ansible-playbook playbooks/bootstrap-k3s.yml

# 3. PKI + cert-manager
./scripts/bootstrap-pki.sh
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace -f k8s/base/cert-manager/helm-values.yaml
kubectl apply -k k8s/base/step-ca/
kubectl apply -f k8s/base/cert-manager/cluster-issuer.yaml

# 4. Demo app
kubectl apply -k k8s/base/demo-app/

# 5. Workstation
ansible-playbook playbooks/setup-workstation.yml -e workstation_ingress_ip=<INGRESS_IP>

# 6. Verify (the MVP)
ssh -J opc@<edge-ip> opc@<workstation-ip>
curl https://app.demo.internal  # HTTP 200, no cert warning
```

## Project Structure

```
infra/tofu/          OpenTofu modules and environments
  modules/network/   VCN, subnets, gateways, security lists
  modules/compute/   VMs (edge, ctrl, workers, workstation)
  environments/poc/  Root module for PoC deployment

ansible/             Ansible configuration management
  roles/common/      Base packages, sysctl, NTP
  roles/hardening/   CIS Level 1, SSH, firewalld, fail2ban
  roles/k3s-server/  K3s control plane
  roles/k3s-agent/   K3s worker join
  roles/cilium/      Cilium CNI installation
  roles/workstation/ CA trust, hosts, SSH, tools
  playbooks/         Orchestration playbooks

k8s/                 Kubernetes manifests
  base/step-ca/      Internal certificate authority
  base/cert-manager/ Certificate lifecycle management
  base/ingress-nginx/ Ingress controller
  base/demo-app/     Demo web application

app/                 Demo app source (Go)
scripts/             Bootstrap scripts (PKI, CoreDNS)
docs/                Architecture and runbook
```

## Reference

Based on [The Standard](../The_Standard/) - a production reference architecture for mid-market organizations.
