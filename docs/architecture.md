# Architecture

## Overview

Production-grade infrastructure demo on Oracle Cloud (OCI), implementing a subset of The Standard IT-101 Phase 1. Minimal scale, production patterns.

## Network Architecture

```
                       ┌─────────────────────────────────────────┐
                       │            OCI VCN 10.0.0.0/16          │
                       │                                         │
    Internet ──────────┤                                         │
         │             │  ┌─────────────────────────────────┐    │
         │             │  │ DMZ 10.0.1.0/24 (public)        │    │
         │             │  │  it101-edge-01  A2.Flex 1/4     │    │
         ├─── HTTPS ──►│  │  it101-edge-02  A2.Flex 1/4     │    │
         │             │  └────────────┬────────────────────┘    │
         │             │               │ HTTP/HTTPS              │
         │             │  ┌────────────▼────────────────────┐    │
         │             │  │ APP 10.0.10.0/24 (private)      │    │
         │             │  │  it101-ctrl-01  A2.Flex 4/12    │    │
         │             │  │  it101-worker-01 A2.Flex 4/6    │    │
         │             │  │  it101-worker-02 A2.Flex 4/6    │    │
         │             │  │                                 │    │
         │             │  │  K3s + Cilium CNI                │    │
         │             │  │  ┌─────────┐ ┌──────────────┐   │    │
         │             │  │  │step-ca  │ │ ingress-nginx│   │    │
         │             │  │  │cert-mgr │ │ demo-app     │   │    │
         │             │  │  └─────────┘ └──────────────┘   │    │
         │             │  └─────────────────────────────────┘    │
         │             │                                         │
         │             │  ┌─────────────────────────────────┐    │
         │             │  │ WORKSTATION 10.0.100.0/24 (priv)│    │
    SSH ──────────────►│  │  workstation VM  DHCP           │    │
         │             │  │  Trusts enterprise CA            │    │
         │             │  │  curl https://app.demo.internal │    │
         │             │  └─────────────────────────────────┘    │
         │             │                                         │
         │             │  ┌─────────────────────────────────┐    │
         │             │  │ MANAGEMENT 10.0.40.0/24 (public)│    │
         │             │  │  SSH + WireGuard entry point     │    │
         │             │  └─────────────────────────────────┘    │
         │             │                                         │
         │             │  DATA 10.0.20.0/24 (reserved)          │
         │             │  IDENTITY 10.0.30.0/24 (reserved)      │
         │             └─────────────────────────────────────────┘
```

## Security Zones

| Zone | CIDR | Access | Purpose |
|------|------|--------|---------|
| DMZ | 10.0.1.0/24 | Public (80, 443) | Edge nodes, TLS termination |
| APP | 10.0.10.0/24 | Private | K3s cluster (ctrl + workers) |
| DATA | 10.0.20.0/24 | Private | Reserved for CloudNativePG |
| IDENTITY | 10.0.30.0/24 | Private | Reserved for Keycloak/OpenBao |
| MANAGEMENT | 10.0.40.0/24 | Public (SSH, WG) | Admin access, VPN endpoint |
| WORKSTATION | 10.0.100.0/24 | Private (DHCP) | Virtual workstation |

## PKI Trust Chain

```
Demo Corp Root CA (offline, 10-year)
    └── Demo Corp Intermediate CA (online, 5-year)
            └── cert-manager (ACME ClusterIssuer)
                    └── app.demo.internal TLS certificate
```

The root CA certificate is distributed to the workstation via Ansible and installed into the OL9 system trust store (`/etc/pki/ca-trust/source/anchors/`). This enables `curl` and browsers to trust certificates issued by the enterprise CA without warnings.

## Compute

| Node | Shape | OCPU | RAM | Subnet | Role |
|------|-------|------|-----|--------|------|
| it101-edge-01 | VM.Standard.A2.Flex | 1 | 4 GB | DMZ | Edge/jump host |
| it101-edge-02 | VM.Standard.A2.Flex | 1 | 4 GB | DMZ | Edge/jump host |
| it101-ctrl-01 | VM.Standard.A2.Flex | 4 | 12 GB | APP | K3s server |
| it101-worker-01 | VM.Standard.A2.Flex | 4 | 6 GB | APP | K3s agent |
| it101-worker-02 | VM.Standard.A2.Flex | 4 | 6 GB | APP | K3s agent |
| workstation | VM.Standard.A2.Flex | 1 | 4 GB | WORKSTATION | Virtual workstation |

## Key Design Decisions

1. **A2.Flex for all VMs** - A1.Flex (Always Free) and E2.1.Micro unavailable in us-chicago-1; A2.Flex (ARM64 Ampere) uses trial credits
2. **K3s not OKE** - No cloud lock-in; portable to any IaaS or bare metal
3. **Cilium not Flannel** - eBPF L7 policies, transparent mTLS, no sidecar overhead
4. **step-ca not FreeIPA Dogtag** - Standalone CA, not tied to identity system
5. **CoreDNS not BIND** - Embedded in K3s, no additional VM needed
6. **Workstation on separate subnet** - Validates network segmentation; DHCP proves dynamic addressing
7. **shell dnf not ansible.builtin.dnf** - Ansible dnf module OOM-kills on low-RAM nodes; shell dnf is safe
8. **buildah not docker** - No Docker daemon needed; builds OCI images directly on ARM64 nodes
