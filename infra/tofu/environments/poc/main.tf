# environments/poc/main.tf
# Root module for the it101 PoC environment.
# Wires together the network and compute modules.
#
# Deployment order:
#   1. Network module (VCN, subnets, gateways, security lists, Object Storage)
#   2. Compute module (all VMs, depends on network outputs)
#
# Usage:
#   cd infra/tofu/environments/poc
#   tofu init -backend-config=.s3.tfbackend   # see backend.tf for bootstrap
#   tofu plan
#   tofu apply

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

# ---------------------------------------------------------------------------
# Network module
# Provisions VCN, all subnets, gateways, security lists, and Object Storage
# ---------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  compartment_id = var.compartment_id
  region         = var.region
  project_name   = var.project_name
  environment    = var.environment

  # VCN
  vcn_cidr      = var.vcn_cidr
  vcn_dns_label = var.vcn_dns_label

  # Subnet CIDRs
  dmz_cidr         = var.dmz_cidr
  app_cidr          = var.app_cidr
  data_cidr         = var.data_cidr
  identity_cidr     = var.identity_cidr
  management_cidr   = var.management_cidr
  workstation_cidr  = var.workstation_cidr

  # Security
  admin_cidr          = var.admin_cidr
  allowed_ssh_sources = var.allowed_ssh_sources

  # Object Storage
  object_storage_namespace = var.object_storage_namespace
  state_bucket_name        = var.state_bucket_name
  loki_bucket_name         = var.loki_bucket_name
  backup_bucket_name       = var.backup_bucket_name

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Compute module
# Provisions all VMs using subnet IDs from the network module
# ---------------------------------------------------------------------------

module "compute" {
  source = "../../modules/compute"

  compartment_id = var.compartment_id
  project_name   = var.project_name
  environment    = var.environment

  # Network references from network module outputs
  subnet_dmz_id         = module.network.subnet_dmz_id
  subnet_app_id         = module.network.subnet_app_id
  subnet_management_id  = module.network.subnet_management_id
  subnet_workstation_id = module.network.subnet_workstation_id

  # SSH access
  ssh_public_key = var.ssh_public_key

  # Images (region-specific OCIDs — see terraform.tfvars.example)
  image_id_ol9_x86   = var.image_id_ol9_x86
  image_id_ol9_arm64 = var.image_id_ol9_arm64

  # Availability domains
  ad_index_edge        = var.ad_index_edge
  ad_index_k3s         = var.ad_index_k3s
  ad_index_workstation = var.ad_index_workstation

  # Shape configuration
  edge_shape        = var.edge_shape
  edge_ocpus        = var.edge_ocpus
  edge_memory_gb    = var.edge_memory_gb
  ctrl_shape        = var.ctrl_shape
  ctrl_ocpus        = var.ctrl_ocpus
  ctrl_memory_gb    = var.ctrl_memory_gb
  worker_shape      = var.worker_shape
  worker_ocpus      = var.worker_ocpus
  worker_memory_gb  = var.worker_memory_gb
  workstation_shape = var.workstation_shape
  workstation_ocpus = var.workstation_ocpus
  workstation_memory_gb = var.workstation_memory_gb

  # Boot volumes
  edge_boot_volume_gb        = var.edge_boot_volume_gb
  ctrl_boot_volume_gb        = var.ctrl_boot_volume_gb
  worker_boot_volume_gb      = var.worker_boot_volume_gb
  workstation_boot_volume_gb = var.workstation_boot_volume_gb

  tags = local.common_tags
}

locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "opentofu"
  }
}
