# modules/compute/variables.tf
# Input variables for the compute module.

variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID where VMs will be created."
}

variable "project_name" {
  type        = string
  description = "Short project identifier used as a prefix in resource display names."
  default     = "it101"
}

variable "environment" {
  type        = string
  description = "Deployment environment label (poc, staging, prod)."
  default     = "poc"

  validation {
    condition     = contains(["poc", "staging", "prod"], var.environment)
    error_message = "environment must be one of: poc, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# Network inputs (from network module outputs)
# ---------------------------------------------------------------------------

variable "subnet_dmz_id" {
  type        = string
  description = "OCID of the DMZ subnet. Edge nodes are placed here."
}

variable "subnet_app_id" {
  type        = string
  description = "OCID of the APP subnet. K3s control and worker nodes are placed here."
}

variable "subnet_management_id" {
  type        = string
  description = "OCID of the MANAGEMENT subnet."
}

variable "subnet_workstation_id" {
  type        = string
  description = "OCID of the WORKSTATION subnet. Virtual workstation is placed here."
}

# ---------------------------------------------------------------------------
# SSH access
# ---------------------------------------------------------------------------

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content (OpenSSH format) for the opc user on all VMs."
  sensitive   = false
}

# ---------------------------------------------------------------------------
# Image selection
#
# OCI image OCIDs are region-specific. Provide the correct OCIDs for
# us-chicago-1. Use 'oci compute image list' to discover them.
#
# Recommended base images for us-chicago-1:
#   Oracle Linux 9 (x86_64) – for AMD Micro edge nodes
#   Oracle Linux 9 (aarch64) – for A2.Flex ARM nodes and workstation
# ---------------------------------------------------------------------------

variable "image_id_ol9_x86" {
  type        = string
  description = "OCI image OCID for Oracle Linux 9 (x86_64) in the target region. Used by AMD Micro edge nodes."
}

variable "image_id_ol9_arm64" {
  type        = string
  description = "OCI image OCID for Oracle Linux 9 (aarch64) in the target region. Used by A2.Flex nodes and workstation."
}

# ---------------------------------------------------------------------------
# Availability Domains
# ---------------------------------------------------------------------------

variable "ad_index_edge" {
  type        = number
  description = "Zero-based index of the availability domain for edge nodes (0, 1, or 2)."
  default     = 0

  validation {
    condition     = var.ad_index_edge >= 0 && var.ad_index_edge <= 2
    error_message = "ad_index_edge must be 0, 1, or 2."
  }
}

variable "ad_index_k3s" {
  type        = number
  description = "Zero-based index of the availability domain for K3s nodes."
  default     = 0

  validation {
    condition     = var.ad_index_k3s >= 0 && var.ad_index_k3s <= 2
    error_message = "ad_index_k3s must be 0, 1, or 2."
  }
}

variable "ad_index_workstation" {
  type        = number
  description = "Zero-based index of the availability domain for the workstation VM."
  default     = 0

  validation {
    condition     = var.ad_index_workstation >= 0 && var.ad_index_workstation <= 2
    error_message = "ad_index_workstation must be 0, 1, or 2."
  }
}

# ---------------------------------------------------------------------------
# Shape configuration
#
# All instances use A2.Flex (VM.Standard.A2.Flex) – ARM64 Ampere.
# E2.1.Micro and A1.Flex are not available in us-chicago-1.
# A2.Flex memory-to-OCPU ratio must be between 1:1 and 64:1.
# ---------------------------------------------------------------------------

variable "edge_shape" {
  type        = string
  description = "OCI shape for edge nodes."
  default     = "VM.Standard.A2.Flex"
}

variable "edge_ocpus" {
  type        = number
  description = "Number of OCPUs for edge nodes (A2.Flex)."
  default     = 1
}

variable "edge_memory_gb" {
  type        = number
  description = "Memory in GB for edge nodes (A2.Flex)."
  default     = 4
}

variable "ctrl_shape" {
  type        = string
  description = "OCI shape for the K3s control node."
  default     = "VM.Standard.A2.Flex"
}

variable "ctrl_ocpus" {
  type        = number
  description = "Number of OCPUs for the K3s control node (A2.Flex)."
  default     = 4
}

variable "ctrl_memory_gb" {
  type        = number
  description = "Memory in GB for the K3s control node (A2.Flex)."
  default     = 12
}

variable "worker_shape" {
  type        = string
  description = "OCI shape for K3s worker nodes."
  default     = "VM.Standard.A2.Flex"
}

variable "worker_ocpus" {
  type        = number
  description = "Number of OCPUs per K3s worker node (A2.Flex)."
  default     = 4
}

variable "worker_memory_gb" {
  type        = number
  description = "Memory in GB per K3s worker node (A2.Flex)."
  default     = 6
}

variable "workstation_shape" {
  type        = string
  description = "OCI shape for the virtual workstation VM."
  default     = "VM.Standard.A2.Flex"
}

variable "workstation_ocpus" {
  type        = number
  description = "Number of OCPUs for the workstation (A2.Flex)."
  default     = 2
}

variable "workstation_memory_gb" {
  type        = number
  description = "Memory in GB for the workstation (A2.Flex)."
  default     = 8
}

# ---------------------------------------------------------------------------
# Boot volumes
# ---------------------------------------------------------------------------

variable "edge_boot_volume_gb" {
  type        = number
  description = "Boot volume size in GB for edge nodes."
  default     = 50
}

variable "ctrl_boot_volume_gb" {
  type        = number
  description = "Boot volume size in GB for the K3s control node."
  default     = 100
}

variable "worker_boot_volume_gb" {
  type        = number
  description = "Boot volume size in GB for K3s worker nodes."
  default     = 100
}

variable "workstation_boot_volume_gb" {
  type        = number
  description = "Boot volume size in GB for the workstation VM."
  default     = 100
}

# ---------------------------------------------------------------------------
# Networking options
# ---------------------------------------------------------------------------

variable "assign_public_ip_to_edge" {
  type        = bool
  description = "Whether to assign a public IPv4 to edge nodes. Required for Caddy Let's Encrypt ACME."
  default     = true
}

variable "assign_public_ip_to_management" {
  type        = bool
  description = "Whether to assign a public IPv4 to the management/bastion node for WireGuard."
  default     = true
}

# ---------------------------------------------------------------------------
# Cloud-init
# ---------------------------------------------------------------------------

variable "edge_user_data" {
  type        = string
  description = "Base64-encoded cloud-init user-data for edge nodes. If empty, module generates a minimal default."
  default     = ""
}

variable "ctrl_user_data" {
  type        = string
  description = "Base64-encoded cloud-init user-data for the K3s control node."
  default     = ""
}

variable "worker_user_data" {
  type        = string
  description = "Base64-encoded cloud-init user-data for K3s worker nodes."
  default     = ""
}

variable "workstation_user_data" {
  type        = string
  description = "Base64-encoded cloud-init user-data for the workstation VM."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Freeform tags applied to all resources in this module."
  default     = {}
}
