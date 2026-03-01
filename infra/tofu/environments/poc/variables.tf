# environments/poc/variables.tf
# Input variables for the poc root module.
# Values are provided via terraform.tfvars (gitignored) or environment variables.

# ---------------------------------------------------------------------------
# OCI Authentication
# ---------------------------------------------------------------------------

variable "tenancy_ocid" {
  type        = string
  description = "OCID of the OCI tenancy."
}

variable "user_ocid" {
  type        = string
  description = "OCID of the OCI IAM user running OpenTofu."
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the OCI API key pair used for authentication."
}

variable "private_key" {
  type        = string
  description = "Contents of the OCI API private key (PEM format). Mark sensitive in production."
  sensitive   = true
}

variable "region" {
  type        = string
  description = "OCI region identifier."
  default     = "us-chicago-1"
}

# ---------------------------------------------------------------------------
# Compartment
# ---------------------------------------------------------------------------

variable "compartment_id" {
  type        = string
  description = "OCID of the compartment where all resources are provisioned."
}

# ---------------------------------------------------------------------------
# Project metadata
# ---------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Short project identifier used as a prefix in all resource names."
  default     = "it101"
}

variable "environment" {
  type        = string
  description = "Environment label."
  default     = "poc"

  validation {
    condition     = contains(["poc", "staging", "prod"], var.environment)
    error_message = "environment must be one of: poc, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# VCN / Networking
# ---------------------------------------------------------------------------

variable "vcn_cidr" {
  type        = string
  description = "IPv4 CIDR for the VCN."
  default     = "10.0.0.0/16"
}

variable "vcn_dns_label" {
  type        = string
  description = "DNS label for the VCN (≤15 lowercase alphanumeric chars)."
  default     = "it101poc"
}

variable "dmz_cidr" {
  type        = string
  description = "CIDR for the DMZ subnet."
  default     = "10.0.1.0/24"
}

variable "app_cidr" {
  type        = string
  description = "CIDR for the APP subnet."
  default     = "10.0.10.0/24"
}

variable "data_cidr" {
  type        = string
  description = "CIDR for the DATA subnet."
  default     = "10.0.20.0/24"
}

variable "identity_cidr" {
  type        = string
  description = "CIDR for the IDENTITY subnet."
  default     = "10.0.30.0/24"
}

variable "management_cidr" {
  type        = string
  description = "CIDR for the MANAGEMENT subnet."
  default     = "10.0.40.0/24"
}

variable "workstation_cidr" {
  type        = string
  description = "CIDR for the WORKSTATION subnet."
  default     = "10.0.100.0/24"
}

variable "admin_cidr" {
  type        = string
  description = "CIDR block from which SSH is permitted to MANAGEMENT subnet nodes."
  default     = "10.0.40.0/24"
}

variable "allowed_ssh_sources" {
  type        = list(string)
  description = "List of CIDRs permitted to SSH into MANAGEMENT nodes over the public internet."
  default     = []
}

# ---------------------------------------------------------------------------
# Object Storage
# ---------------------------------------------------------------------------

variable "object_storage_namespace" {
  type        = string
  description = "OCI Object Storage namespace. Retrieve with: oci os ns get --query 'data' --raw-output"
}

variable "state_bucket_name" {
  type        = string
  description = "Name of the OCI Object Storage bucket for OpenTofu state."
  default     = "it101-poc-tofu-state"
}

variable "loki_bucket_name" {
  type        = string
  description = "Name of the OCI Object Storage bucket for Loki log chunks."
  default     = "it101-poc-loki-chunks"
}

variable "backup_bucket_name" {
  type        = string
  description = "Name of the OCI Object Storage bucket for Restic/Velero backups."
  default     = "it101-poc-backups"
}

# ---------------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------------

variable "ssh_public_key" {
  type        = string
  description = "SSH public key (OpenSSH format) injected into all VMs as the opc user's authorized_keys."
}

# ---------------------------------------------------------------------------
# OCI Image OCIDs (us-chicago-1)
#
# Retrieve current OCIDs with:
#   oci compute image list \
#     --compartment-id <TENANCY_OCID> \
#     --operating-system "Oracle Linux" \
#     --operating-system-version "9" \
#     --sort-by TIMECREATED \
#     --sort-order DESC \
#     --query 'data[*].{id:id, display:\"display-name\", shape:"shape"}' \
#     | jq 'map(select(.display | test("aarch64")))'
# ---------------------------------------------------------------------------

variable "image_id_ol9_x86" {
  type        = string
  description = "OCI image OCID for Oracle Linux 9 (x86_64) in us-chicago-1."
}

variable "image_id_ol9_arm64" {
  type        = string
  description = "OCI image OCID for Oracle Linux 9 (aarch64) in us-chicago-1."
}

# ---------------------------------------------------------------------------
# Availability Domain selection
# ---------------------------------------------------------------------------

variable "ad_index_edge" {
  type        = number
  description = "Availability domain index (0-2) for edge nodes."
  default     = 0
}

variable "ad_index_k3s" {
  type        = number
  description = "Availability domain index (0-2) for K3s nodes."
  default     = 0
}

variable "ad_index_workstation" {
  type        = number
  description = "Availability domain index (0-2) for the workstation VM."
  default     = 0
}

# ---------------------------------------------------------------------------
# Instance shapes
# ---------------------------------------------------------------------------

variable "edge_shape" {
  type        = string
  description = "Shape for edge nodes."
  default     = "VM.Standard.A2.Flex"
}

variable "edge_ocpus" {
  type        = number
  description = "OCPUs for edge nodes."
  default     = 1
}

variable "edge_memory_gb" {
  type        = number
  description = "Memory (GB) for edge nodes."
  default     = 4
}

variable "ctrl_shape" {
  type        = string
  description = "Shape for K3s control node. Use A2.Flex, NOT A1.Flex (exhausted in Chicago)."
  default     = "VM.Standard.A2.Flex"
}

variable "ctrl_ocpus" {
  type        = number
  description = "OCPUs for K3s control node."
  default     = 4
}

variable "ctrl_memory_gb" {
  type        = number
  description = "Memory (GB) for K3s control node."
  default     = 12
}

variable "worker_shape" {
  type        = string
  description = "Shape for K3s worker nodes."
  default     = "VM.Standard.A2.Flex"
}

variable "worker_ocpus" {
  type        = number
  description = "OCPUs per K3s worker node."
  default     = 4
}

variable "worker_memory_gb" {
  type        = number
  description = "Memory (GB) per K3s worker node."
  default     = 6
}

variable "workstation_shape" {
  type        = string
  description = "Shape for the virtual workstation."
  default     = "VM.Standard.A2.Flex"
}

variable "workstation_ocpus" {
  type        = number
  description = "OCPUs for the workstation."
  default     = 2
}

variable "workstation_memory_gb" {
  type        = number
  description = "Memory (GB) for the workstation."
  default     = 8
}

# ---------------------------------------------------------------------------
# Boot volume sizes
# ---------------------------------------------------------------------------

variable "edge_boot_volume_gb" {
  type        = number
  description = "Boot volume size (GB) for edge nodes."
  default     = 50
}

variable "ctrl_boot_volume_gb" {
  type        = number
  description = "Boot volume size (GB) for K3s control node."
  default     = 100
}

variable "worker_boot_volume_gb" {
  type        = number
  description = "Boot volume size (GB) for K3s worker nodes."
  default     = 100
}

variable "workstation_boot_volume_gb" {
  type        = number
  description = "Boot volume size (GB) for the workstation VM."
  default     = 100
}
