# The Standard Demo - CLAUDE.md

## Project Overview

Production-grade infrastructure demo on Oracle Cloud (OCI), implementing a subset of The Standard (IT-101 Phase 1). This is a minimal-scale but production-correct deployment.

**Reference architecture:** ~/The_Standard/
**Target cloud:** OCI us-chicago-1
**Domain:** demo.internal (internal placeholder)

## Architecture

### Network Zones
- **DMZ** (10.0.1.0/24): Edge nodes (Caddy TLS termination)
- **APP** (10.0.10.0/24): K3s control + workers
- **DATA** (10.0.20.0/24): Reserved for databases
- **IDENTITY** (10.0.30.0/24): Reserved for Keycloak/OpenBao
- **MANAGEMENT** (10.0.40.0/24): Admin access, VPN
- **WORKSTATION** (10.0.100.0/24): Virtual workstation (DHCP, separate from servers)

### Compute
- 2x AMD Micro (1 OCPU/1 GB) - edge nodes in DMZ
- 1x ARM A2.Flex (4 OCPU/12 GB) - K3s control in APP
- 2x ARM A2.Flex (4 OCPU/6 GB) - K3s workers in APP
- 1x Workstation VM in WORKSTATION subnet (DHCP)

### Key Components
- **IaC:** OpenTofu (remote state on OCI Object Storage)
- **Config:** Ansible (vault for bootstrap secrets only)
- **K8s:** K3s with Cilium CNI (eBPF)
- **PKI:** step-ca (root + intermediate) → cert-manager → service certs
- **Ingress:** ingress-nginx (in-cluster)
- **App:** Simple demo web app at https://app.demo.internal

## Non-Negotiable Rules

1. **Deployment ordering is sacred.** Network → Compute → OS hardening → K3s+Cilium → PKI → Apps. Do not skip steps.
2. **Remote state before first apply.** Configure backend.tf with OCI Object Storage before `tofu init`.
3. **Fully qualified image references only.** `docker.io/library/nginx:alpine`, never `nginx:alpine`.
4. **Resource requests and limits on all pods.** No exceptions.
5. **ArgoCD server-side apply.** Always `kubectl apply --server-side --force-conflicts` for CRDs.
6. **Secrets never in git.** Ansible Vault for bootstrap only; OpenBao for runtime.
7. **group_vars inside inventory directory.** `ansible/inventory/group_vars/`, not `ansible/group_vars/`.
8. **Shell dnf on low-RAM nodes.** Use shell `dnf` invocations, not `ansible.builtin.dnf`, on nodes < 4 GB RAM.
9. **ARM64 images required.** All containers must support `linux/arm64`. Verify before adopting.
10. **Cilium before workloads.** K3s must use `--flannel-backend=none`. Cannot be changed after install.

## MVP Deliverables

1. Working K3s cluster on OCI
2. Internal PKI with enterprise CA trust
3. Demo web app accessible at https://app.demo.internal
4. Virtual workstation on separate network (DHCP)
5. Workstation trusts enterprise CA (no cert warnings)
6. SSH access to workstation from admin machine

## IaC Structure

```
infra/tofu/
  environments/poc/     # Root module - ties modules together
  modules/
    network/            # VCN, subnets, gateways, security lists
    compute/            # VMs, SSH keys, cloud-init
    object-storage/     # Buckets for state, backups

ansible/
  inventory/
    group_vars/all/     # Variables (MUST be inside inventory/)
  roles/
    common/             # Base packages, sysctl, NTP
    hardening/          # CIS Level 1, SSH, firewalld, fail2ban
    k3s-server/         # K3s server install
    k3s-agent/          # K3s agent join
    cilium/             # Cilium CNI via Helm
    workstation/        # Workstation setup, CA trust, domain join
  playbooks/

k8s/
  base/                 # Kubernetes manifests
    step-ca/            # Internal CA
    cert-manager/       # Certificate lifecycle
    ingress-nginx/      # Ingress controller
    demo-app/           # Demo application
  argocd/               # ArgoCD app definitions

app/                    # Demo application source code
```
