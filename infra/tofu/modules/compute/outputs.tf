# modules/compute/outputs.tf
# Outputs for Ansible inventory generation and inter-module references.
#
# All IP address outputs include both public (where assigned) and private IPs
# so that Ansible can build a complete inventory without additional API calls.

# ---------------------------------------------------------------------------
# Edge nodes
# ---------------------------------------------------------------------------

output "edge_instance_ids" {
  description = "List of OCIDs for the two edge node instances."
  value       = [for inst in oci_core_instance.edge : inst.id]
}

output "edge_public_ips" {
  description = "List of public IPv4 addresses for edge nodes (order matches edge_instance_ids)."
  value       = [for inst in oci_core_instance.edge : inst.public_ip]
}

output "edge_private_ips" {
  description = "List of private IPv4 addresses for edge nodes."
  value       = [for inst in oci_core_instance.edge : inst.private_ip]
}

output "edge_display_names" {
  description = "List of display names for edge nodes."
  value       = [for inst in oci_core_instance.edge : inst.display_name]
}

# ---------------------------------------------------------------------------
# K3s control node
# ---------------------------------------------------------------------------

output "ctrl_instance_id" {
  description = "OCID of the K3s control node."
  value       = oci_core_instance.ctrl.id
}

output "ctrl_private_ip" {
  description = "Private IPv4 address of the K3s control node (APP subnet)."
  value       = oci_core_instance.ctrl.private_ip
}

output "ctrl_display_name" {
  description = "Display name of the K3s control node."
  value       = oci_core_instance.ctrl.display_name
}

# ---------------------------------------------------------------------------
# K3s worker nodes
# ---------------------------------------------------------------------------

output "worker_instance_ids" {
  description = "List of OCIDs for the K3s worker nodes."
  value       = [for inst in oci_core_instance.worker : inst.id]
}

output "worker_private_ips" {
  description = "List of private IPv4 addresses for K3s worker nodes."
  value       = [for inst in oci_core_instance.worker : inst.private_ip]
}

output "worker_display_names" {
  description = "List of display names for K3s worker nodes."
  value       = [for inst in oci_core_instance.worker : inst.display_name]
}

# ---------------------------------------------------------------------------
# Virtual workstation
# ---------------------------------------------------------------------------

output "workstation_instance_id" {
  description = "OCID of the virtual workstation VM."
  value       = oci_core_instance.workstation.id
}

output "workstation_private_ip" {
  description = "Private IPv4 address of the workstation (DHCP-assigned from WORKSTATION subnet)."
  value       = oci_core_instance.workstation.private_ip
}

output "workstation_display_name" {
  description = "Display name of the workstation VM."
  value       = oci_core_instance.workstation.display_name
}

# ---------------------------------------------------------------------------
# Aggregated Ansible inventory map
# Convenient structured output for use in ansible-inventory scripts or
# the Ansible dynamic inventory OCI plugin.
# ---------------------------------------------------------------------------

output "ansible_inventory" {
  description = "Structured map of all VM IPs suitable for generating an Ansible inventory."
  value = {
    edge = {
      for i, inst in oci_core_instance.edge : inst.display_name => {
        public_ip  = inst.public_ip
        private_ip = inst.private_ip
        group      = "edge"
        arch       = "x86_64"
      }
    }
    k3s_control = {
      (oci_core_instance.ctrl.display_name) = {
        public_ip  = null
        private_ip = oci_core_instance.ctrl.private_ip
        group      = "k3s_control"
        arch       = "aarch64"
      }
    }
    k3s_workers = {
      for i, inst in oci_core_instance.worker : inst.display_name => {
        public_ip  = null
        private_ip = inst.private_ip
        group      = "k3s_workers"
        arch       = "aarch64"
      }
    }
    workstation = {
      (oci_core_instance.workstation.display_name) = {
        public_ip  = null
        private_ip = oci_core_instance.workstation.private_ip
        group      = "workstation"
        arch       = "aarch64"
      }
    }
  }
}
