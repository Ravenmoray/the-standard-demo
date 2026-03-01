# environments/poc/outputs.tf
# Outputs from the poc root module.
# Used for:
#   - Ansible inventory generation
#   - DNS record creation
#   - Post-apply verification
#   - Documentation / runbooks

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

output "vcn_id" {
  description = "OCID of the VCN."
  value       = module.network.vcn_id
}

output "subnet_ids" {
  description = "Map of subnet zone name to OCID."
  value = {
    dmz         = module.network.subnet_dmz_id
    app         = module.network.subnet_app_id
    data        = module.network.subnet_data_id
    identity    = module.network.subnet_identity_id
    management  = module.network.subnet_management_id
    workstation = module.network.subnet_workstation_id
  }
}

# ---------------------------------------------------------------------------
# Object Storage
# ---------------------------------------------------------------------------

output "object_storage_buckets" {
  description = "Object Storage bucket names for documentation and Ansible variable injection."
  value = {
    state  = module.network.state_bucket_name
    loki   = module.network.loki_bucket_name
    backup = module.network.backup_bucket_name
  }
}

output "object_storage_namespace" {
  description = "OCI Object Storage namespace."
  value       = module.network.object_storage_namespace
}

# ---------------------------------------------------------------------------
# Edge nodes
# ---------------------------------------------------------------------------

output "edge_public_ips" {
  description = "Public IPs of the two edge nodes. Use these for DNS A records and Caddy ACME."
  value       = module.compute.edge_public_ips
}

output "edge_private_ips" {
  description = "Private IPs of the edge nodes (DMZ subnet)."
  value       = module.compute.edge_private_ips
}

# ---------------------------------------------------------------------------
# K3s cluster
# ---------------------------------------------------------------------------

output "k3s_ctrl_private_ip" {
  description = "Private IP of the K3s control node. Use for kubeconfig server address (via WireGuard)."
  value       = module.compute.ctrl_private_ip
}

output "k3s_worker_private_ips" {
  description = "Private IPs of the K3s worker nodes."
  value       = module.compute.worker_private_ips
}

# ---------------------------------------------------------------------------
# Workstation
# ---------------------------------------------------------------------------

output "workstation_private_ip" {
  description = "Private IP of the virtual workstation (DHCP-assigned from WORKSTATION subnet)."
  value       = module.compute.workstation_private_ip
}

# ---------------------------------------------------------------------------
# Ansible inventory helper
# ---------------------------------------------------------------------------

output "ansible_inventory" {
  description = "Complete VM inventory map for Ansible dynamic inventory or ini generation."
  value       = module.compute.ansible_inventory
}

# ---------------------------------------------------------------------------
# Quick-start SSH commands (post-apply convenience)
# ---------------------------------------------------------------------------

output "ssh_commands" {
  description = "SSH commands for initial connectivity verification. Replace <your-key> with your private key path."
  value = {
    edge_01     = "ssh -i <your-key> opc@${module.compute.edge_public_ips[0]}"
    edge_02     = "ssh -i <your-key> opc@${module.compute.edge_public_ips[1]}"
    ctrl_01_via_bastion     = "ssh -i <your-key> -J opc@${module.compute.edge_public_ips[0]} opc@${module.compute.ctrl_private_ip}"
    workstation_via_bastion = "ssh -i <your-key> -J opc@${module.compute.edge_public_ips[0]} opc@${module.compute.workstation_private_ip}"
  }
}
