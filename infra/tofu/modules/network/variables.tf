# modules/network/variables.tf
# Input variables for the network module

variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID where all network resources will be created."
}

variable "region" {
  type        = string
  description = "OCI region (e.g., us-chicago-1)."
}

variable "project_name" {
  type        = string
  description = "Short project identifier used as a prefix in all resource display names."
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

# VCN
variable "vcn_cidr" {
  type        = string
  description = "IPv4 CIDR block for the VCN."
  default     = "10.0.0.0/16"
}

variable "vcn_dns_label" {
  type        = string
  description = "DNS label for the VCN. Must be ≤ 15 lowercase alphanumeric chars, unique per tenancy."
  default     = "it101poc"
}

# Subnet CIDRs (one variable per security zone)
variable "dmz_cidr" {
  type        = string
  description = "CIDR for the DMZ subnet (edge/ingress nodes, Caddy TLS termination)."
  default     = "10.0.1.0/24"
}

variable "app_cidr" {
  type        = string
  description = "CIDR for the APP subnet (K3s control plane and worker nodes)."
  default     = "10.0.10.0/24"
}

variable "data_cidr" {
  type        = string
  description = "CIDR for the DATA subnet (reserved for databases, CloudNativePG)."
  default     = "10.0.20.0/24"
}

variable "identity_cidr" {
  type        = string
  description = "CIDR for the IDENTITY subnet (reserved for Keycloak, OpenBao)."
  default     = "10.0.30.0/24"
}

variable "management_cidr" {
  type        = string
  description = "CIDR for the MANAGEMENT subnet (admin access, VPN gateway)."
  default     = "10.0.40.0/24"
}

variable "workstation_cidr" {
  type        = string
  description = "CIDR for the WORKSTATION subnet (virtual workstation, DHCP assignment)."
  default     = "10.0.100.0/24"
}

# Object Storage bucket names
variable "state_bucket_name" {
  type        = string
  description = "Name of the OCI Object Storage bucket used for OpenTofu remote state."
}

variable "loki_bucket_name" {
  type        = string
  description = "Name of the OCI Object Storage bucket used for Loki log chunk storage."
}

variable "backup_bucket_name" {
  type        = string
  description = "Name of the OCI Object Storage bucket used for Restic/Velero backups."
}

variable "object_storage_namespace" {
  type        = string
  description = "OCI Object Storage namespace (tenancy-level, retrieve via 'oci os ns get')."
}

# Access control
variable "admin_cidr" {
  type        = string
  description = "CIDR of the admin management network allowed SSH access (e.g., WireGuard VPN CIDR or your office IP /32)."
  default     = "10.0.40.0/24"
}

variable "allowed_ssh_sources" {
  type        = list(string)
  description = "Additional CIDRs permitted to reach SSH on management nodes (e.g., admin workstation public IPs)."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Freeform tags applied to all resources in this module."
  default     = {}
}
