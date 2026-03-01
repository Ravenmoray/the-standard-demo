# modules/network/outputs.tf
# Outputs consumed by the compute module and the poc environment root module.

output "vcn_id" {
  description = "OCID of the VCN."
  value       = oci_core_vcn.main.id
}

output "vcn_cidr" {
  description = "IPv4 CIDR block of the VCN."
  value       = var.vcn_cidr
}

# Subnet IDs
output "subnet_dmz_id" {
  description = "OCID of the DMZ subnet (edge/ingress nodes)."
  value       = oci_core_subnet.dmz.id
}

output "subnet_app_id" {
  description = "OCID of the APP subnet (K3s nodes)."
  value       = oci_core_subnet.app.id
}

output "subnet_data_id" {
  description = "OCID of the DATA subnet (databases)."
  value       = oci_core_subnet.data.id
}

output "subnet_identity_id" {
  description = "OCID of the IDENTITY subnet (Keycloak, OpenBao)."
  value       = oci_core_subnet.identity.id
}

output "subnet_management_id" {
  description = "OCID of the MANAGEMENT subnet (admin/VPN)."
  value       = oci_core_subnet.management.id
}

output "subnet_workstation_id" {
  description = "OCID of the WORKSTATION subnet (virtual workstation, DHCP)."
  value       = oci_core_subnet.workstation.id
}

# Subnet CIDRs (consumed by security list rules in compute module if needed)
output "subnet_dmz_cidr" {
  description = "CIDR of the DMZ subnet."
  value       = var.dmz_cidr
}

output "subnet_app_cidr" {
  description = "CIDR of the APP subnet."
  value       = var.app_cidr
}

output "subnet_management_cidr" {
  description = "CIDR of the MANAGEMENT subnet."
  value       = var.management_cidr
}

output "subnet_workstation_cidr" {
  description = "CIDR of the WORKSTATION subnet."
  value       = var.workstation_cidr
}

# Gateway IDs
output "internet_gateway_id" {
  description = "OCID of the Internet Gateway."
  value       = oci_core_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "OCID of the NAT Gateway."
  value       = oci_core_nat_gateway.main.id
}

output "service_gateway_id" {
  description = "OCID of the Service Gateway."
  value       = oci_core_service_gateway.main.id
}

# Security list IDs
output "security_list_dmz_id" {
  description = "OCID of the DMZ security list."
  value       = oci_core_security_list.dmz.id
}

output "security_list_app_id" {
  description = "OCID of the APP security list."
  value       = oci_core_security_list.app.id
}

output "security_list_management_id" {
  description = "OCID of the MANAGEMENT security list."
  value       = oci_core_security_list.management.id
}

# Object Storage bucket names (for Ansible inventory and documentation)
output "state_bucket_name" {
  description = "Name of the OpenTofu remote state bucket."
  value       = oci_objectstorage_bucket.state.name
}

output "loki_bucket_name" {
  description = "Name of the Loki log chunks bucket."
  value       = oci_objectstorage_bucket.loki.name
}

output "backup_bucket_name" {
  description = "Name of the Restic/Velero backup bucket."
  value       = oci_objectstorage_bucket.backup.name
}

output "object_storage_namespace" {
  description = "OCI Object Storage namespace."
  value       = var.object_storage_namespace
}
