# modules/network/main.tf
# OCI networking resources: VCN, subnets, gateways, route tables, security lists.
#
# Security zone layout:
#   DMZ         (10.0.1.0/24)   – edge/ingress nodes, public-facing
#   APP         (10.0.10.0/24)  – K3s cluster nodes, private
#   DATA        (10.0.20.0/24)  – databases (CloudNativePG), private
#   IDENTITY    (10.0.30.0/24)  – Keycloak, OpenBao, private
#   MANAGEMENT  (10.0.40.0/24)  – admin/VPN, restricted public ingress
#   WORKSTATION (10.0.100.0/24) – virtual workstation, DHCP, private

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    project     = var.project_name
    environment = var.environment
    managed_by  = "opentofu"
  })
}

# ---------------------------------------------------------------------------
# VCN
# ---------------------------------------------------------------------------

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  display_name   = "${local.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = var.vcn_dns_label

  freeform_tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Gateways
# ---------------------------------------------------------------------------

# Internet Gateway – DMZ and MANAGEMENT subnets need public egress/ingress
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-igw"
  enabled        = true

  freeform_tags = local.common_tags
}

# NAT Gateway – private subnets need outbound internet (package updates, etc.)
resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-ngw"
  block_traffic  = false

  freeform_tags = local.common_tags
}

# Service Gateway – private subnets reach OCI services (Object Storage) without
# traversing the public internet
resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sgw"

  services {
    service_id = data.oci_core_services.all_oci_services.services[0].id
  }

  freeform_tags = local.common_tags
}

data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------

# Public route table – default route via IGW (for DMZ and MANAGEMENT)
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-rt-public"

  route_rules {
    description       = "Default route to internet via IGW"
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }

  freeform_tags = local.common_tags
}

# Private route table – default via NAT, OCI services via SGW
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-rt-private"

  route_rules {
    description       = "Default route to internet via NAT gateway"
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  route_rules {
    description       = "OCI services via service gateway (Object Storage, etc.)"
    destination       = data.oci_core_services.all_oci_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }

  freeform_tags = local.common_tags
}

# Workstation route table – NAT egress only; no public IP assignment
resource "oci_core_route_table" "workstation" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-rt-workstation"

  route_rules {
    description       = "Default route to internet via NAT gateway"
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  freeform_tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Security Lists
# ---------------------------------------------------------------------------

# --- DMZ Security List ---
# Edge nodes: accept HTTP/HTTPS from anywhere, SSH from MANAGEMENT only.
resource "oci_core_security_list" "dmz" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sl-dmz"

  # Egress: allow all outbound
  egress_security_rules {
    description = "Allow all outbound traffic"
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Ingress: HTTPS from internet
  ingress_security_rules {
    description = "HTTPS from internet"
    source      = "0.0.0.0/0"
    protocol    = "6" # TCP
    stateless   = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Ingress: HTTP from internet (redirect to HTTPS via Caddy)
  ingress_security_rules {
    description = "HTTP from internet (Caddy will redirect to HTTPS)"
    source      = "0.0.0.0/0"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 80
      max = 80
    }
  }

  # Ingress: SSH from MANAGEMENT subnet only
  ingress_security_rules {
    description = "SSH from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress: Allow ICMP ping from VCN for connectivity testing
  ingress_security_rules {
    description = "ICMP echo from VCN"
    source      = var.vcn_cidr
    protocol    = "1" # ICMP
    stateless   = false

    icmp_options {
      type = 8
      code = 0
    }
  }

  freeform_tags = local.common_tags
}

# --- APP Security List ---
# K3s nodes: inter-node communication, K3s API, SSH from MANAGEMENT.
resource "oci_core_security_list" "app" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sl-app"

  # Egress: allow all outbound
  egress_security_rules {
    description = "Allow all outbound traffic"
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Ingress: SSH from MANAGEMENT subnet
  ingress_security_rules {
    description = "SSH from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress: K3s API server from within APP subnet (inter-node)
  ingress_security_rules {
    description = "K3s API (6443) within APP subnet"
    source      = var.app_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Ingress: K3s API from MANAGEMENT (kubectl from admin)
  ingress_security_rules {
    description = "K3s API (6443) from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Ingress: All TCP within APP subnet (inter-node communication: Cilium, etcd, kubelet)
  ingress_security_rules {
    description = "All TCP within APP subnet for K3s inter-node communication"
    source      = var.app_cidr
    protocol    = "6"
    stateless   = false
  }

  # Ingress: All UDP within APP subnet (Cilium eBPF, VXLAN)
  ingress_security_rules {
    description = "All UDP within APP subnet for Cilium/VXLAN"
    source      = var.app_cidr
    protocol    = "17"
    stateless   = false
  }

  # Ingress: WireGuard from MANAGEMENT (VPN mesh)
  ingress_security_rules {
    description = "WireGuard VPN (51820/UDP) from MANAGEMENT"
    source      = var.management_cidr
    protocol    = "17"
    stateless   = false

    udp_options {
      min = 51820
      max = 51820
    }
  }

  # Ingress: HTTP/HTTPS from DMZ (Caddy reverse-proxy to ingress-nginx)
  ingress_security_rules {
    description = "HTTP from DMZ (ingress-nginx backend)"
    source      = var.dmz_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    description = "HTTPS from DMZ (ingress-nginx backend)"
    source      = var.dmz_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Ingress: NodePort range from DMZ (for LoadBalancer-type services if needed)
  ingress_security_rules {
    description = "NodePort range from DMZ"
    source      = var.dmz_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # Ingress: ICMP from VCN
  ingress_security_rules {
    description = "ICMP echo from VCN"
    source      = var.vcn_cidr
    protocol    = "1"
    stateless   = false

    icmp_options {
      type = 8
      code = 0
    }
  }

  freeform_tags = local.common_tags
}

# --- DATA Security List ---
# Reserved for databases; locked to APP/IDENTITY subnet access only.
resource "oci_core_security_list" "data" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sl-data"

  egress_security_rules {
    description = "Allow all outbound traffic"
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # SSH from MANAGEMENT only
  ingress_security_rules {
    description = "SSH from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # PostgreSQL from APP (K3s pods via CloudNativePG)
  ingress_security_rules {
    description = "PostgreSQL (5432) from APP subnet"
    source      = var.app_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 5432
      max = 5432
    }
  }

  # PostgreSQL from IDENTITY (Keycloak DB access)
  ingress_security_rules {
    description = "PostgreSQL (5432) from IDENTITY subnet"
    source      = var.identity_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 5432
      max = 5432
    }
  }

  # All traffic within DATA subnet (replication)
  ingress_security_rules {
    description = "All TCP within DATA subnet (replication)"
    source      = var.data_cidr
    protocol    = "6"
    stateless   = false
  }

  ingress_security_rules {
    description = "ICMP echo from VCN"
    source      = var.vcn_cidr
    protocol    = "1"
    stateless   = false

    icmp_options {
      type = 8
      code = 0
    }
  }

  freeform_tags = local.common_tags
}

# --- IDENTITY Security List ---
# Reserved for Keycloak, OpenBao; locked to known consumers.
resource "oci_core_security_list" "identity" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sl-identity"

  egress_security_rules {
    description = "Allow all outbound traffic"
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # SSH from MANAGEMENT
  ingress_security_rules {
    description = "SSH from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTPS (Keycloak, OpenBao) from APP subnet
  ingress_security_rules {
    description = "HTTPS (8443/443) from APP subnet (service auth)"
    source      = var.app_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  # OpenBao API (8200) from APP
  ingress_security_rules {
    description = "OpenBao API (8200) from APP subnet"
    source      = var.app_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 8200
      max = 8200
    }
  }

  # Keycloak HTTP (8080) from APP (in-cluster)
  ingress_security_rules {
    description = "Keycloak HTTP (8080) from APP subnet"
    source      = var.app_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 8080
      max = 8080
    }
  }

  # All traffic within IDENTITY
  ingress_security_rules {
    description = "All TCP within IDENTITY subnet"
    source      = var.identity_cidr
    protocol    = "6"
    stateless   = false
  }

  ingress_security_rules {
    description = "ICMP echo from VCN"
    source      = var.vcn_cidr
    protocol    = "1"
    stateless   = false

    icmp_options {
      type = 8
      code = 0
    }
  }

  freeform_tags = local.common_tags
}

# --- MANAGEMENT Security List ---
# Admin access. SSH from allowed_ssh_sources + WireGuard from anywhere.
resource "oci_core_security_list" "management" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sl-management"

  egress_security_rules {
    description = "Allow all outbound traffic"
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # SSH from anywhere (admin workstations connecting over internet to management jump point)
  # Further restrict this to allowed_ssh_sources in production.
  dynamic "ingress_security_rules" {
    for_each = length(var.allowed_ssh_sources) > 0 ? var.allowed_ssh_sources : ["0.0.0.0/0"]
    content {
      description = "SSH from admin source: ${ingress_security_rules.value}"
      source      = ingress_security_rules.value
      protocol    = "6"
      stateless   = false

      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  # WireGuard VPN from anywhere (admins connect from dynamic IPs)
  ingress_security_rules {
    description = "WireGuard VPN (51820/UDP) from internet"
    source      = "0.0.0.0/0"
    protocol    = "17"
    stateless   = false

    udp_options {
      min = 51820
      max = 51820
    }
  }

  # All traffic within MANAGEMENT
  ingress_security_rules {
    description = "All TCP within MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false
  }

  ingress_security_rules {
    description = "ICMP echo from VCN"
    source      = var.vcn_cidr
    protocol    = "1"
    stateless   = false

    icmp_options {
      type = 8
      code = 0
    }
  }

  freeform_tags = local.common_tags
}

# --- WORKSTATION Security List ---
# Virtual workstation subnet. DHCP assignment, SSH from MANAGEMENT.
resource "oci_core_security_list" "workstation" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sl-workstation"

  egress_security_rules {
    description = "Allow all outbound traffic"
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # SSH from MANAGEMENT subnet (admin access to workstation)
  ingress_security_rules {
    description = "SSH from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # RDP (3389) from MANAGEMENT (optional; for GUI workstation sessions)
  ingress_security_rules {
    description = "RDP (3389) from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 3389
      max = 3389
    }
  }

  # VNC (5900) from MANAGEMENT
  ingress_security_rules {
    description = "VNC (5900) from MANAGEMENT subnet"
    source      = var.management_cidr
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 5900
      max = 5900
    }
  }

  ingress_security_rules {
    description = "ICMP echo from VCN"
    source      = var.vcn_cidr
    protocol    = "1"
    stateless   = false

    icmp_options {
      type = 8
      code = 0
    }
  }

  freeform_tags = local.common_tags
}

# ---------------------------------------------------------------------------
# DHCP Options
# ---------------------------------------------------------------------------

# Custom DHCP options for WORKSTATION subnet to use OCI VCN resolver.
# The OCI VCN resolver provides hostname resolution for the internal domain.
resource "oci_core_dhcp_options" "workstation" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-dhcp-workstation"

  # Domain name search list uses the VCN's DNS domain
  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusCustom"
    # OCI VCN resolver first, then quad-9 as fallback
    custom_dns_servers = ["9.9.9.9", "149.112.112.112"]
  }

  options {
    type                = "SearchDomain"
    search_domain_names = ["${var.vcn_dns_label}.oraclevcn.com"]
  }

  freeform_tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

# DMZ – public subnet; edge nodes get public IPs
resource "oci_core_subnet" "dmz" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-subnet-dmz"
  cidr_block                 = var.dmz_cidr
  dns_label                  = "dmz"
  prohibit_public_ip_on_vnic = false # Edge nodes need public IPs
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.dmz.id]

  freeform_tags = local.common_tags
}

# APP – private subnet; K3s nodes, no public IPs
resource "oci_core_subnet" "app" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-subnet-app"
  cidr_block                 = var.app_cidr
  dns_label                  = "app"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.app.id]

  freeform_tags = local.common_tags
}

# DATA – private subnet; reserved for databases
resource "oci_core_subnet" "data" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-subnet-data"
  cidr_block                 = var.data_cidr
  dns_label                  = "data"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.data.id]

  freeform_tags = local.common_tags
}

# IDENTITY – private subnet; reserved for Keycloak/OpenBao
resource "oci_core_subnet" "identity" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-subnet-identity"
  cidr_block                 = var.identity_cidr
  dns_label                  = "identity"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.identity.id]

  freeform_tags = local.common_tags
}

# MANAGEMENT – public subnet; jump host / VPN endpoint gets public IP
resource "oci_core_subnet" "management" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-subnet-management"
  cidr_block                 = var.management_cidr
  dns_label                  = "mgmt"
  prohibit_public_ip_on_vnic = false # Management node needs public IP for WireGuard
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.management.id]

  freeform_tags = local.common_tags
}

# WORKSTATION – private subnet; DHCP, no public IPs; separate from server subnets
resource "oci_core_subnet" "workstation" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${local.name_prefix}-subnet-workstation"
  cidr_block                 = var.workstation_cidr
  dns_label                  = "ws"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.workstation.id
  security_list_ids          = [oci_core_security_list.workstation.id]
  dhcp_options_id            = oci_core_dhcp_options.workstation.id

  freeform_tags = local.common_tags
}
