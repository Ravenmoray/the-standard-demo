# modules/compute/cloud_init.tf
# Default cloud-init templates for each VM role.
#
# These templates perform minimal bootstrapping:
#   - Set hostname
#   - Disable root SSH password auth
#   - Install curl, chrony, firewalld
#   - Enable chrony for NTP (required by Kubernetes)
#   - Resize boot partition to full volume size
#   - Signal cloud-init completion
#
# Full OS hardening (CIS Level 1, fail2ban, sysctl tuning) is handled
# by the Ansible hardening role — not here. cloud-init is only for
# the minimum required to make the node reachable by Ansible.
#
# NOTE: On OCI, the default user is 'opc' with passwordless sudo.
# Oracle Linux 9 images include cloud-init and OCI guest tools by default.

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    project     = var.project_name
    environment = var.environment
    managed_by  = "opentofu"
  })

  # Default cloud-init for edge nodes (AMD x86, Caddy + WireGuard target)
  edge_cloud_init_default = <<-CLOUDINIT
    #cloud-config
    # Edge node bootstrap — minimal setup before Ansible
    hostname: ${local.name_prefix}-edge-PLACEHOLDER
    fqdn: ${local.name_prefix}-edge-PLACEHOLDER.demo.internal
    manage_etc_hosts: true

    # Disable root login; opc user is the admin account
    disable_root: true

    # Grow root partition to fill the provisioned boot volume
    growpart:
      mode: auto
      devices: ['/']
    resize_rootfs: true

    package_update: false
    package_upgrade: false

    # Minimal packages required for Ansible connectivity and basic ops
    # Full package installation is handled by Ansible common role
    packages:
      - chrony
      - firewalld
      - curl
      - python3

    runcmd:
      - systemctl enable --now chronyd
      - systemctl enable --now firewalld
      - chronyc makestep
      - timedatectl set-timezone UTC

    final_message: "Edge node bootstrap complete after $UPTIME seconds"
    CLOUDINIT

  # Default cloud-init for K3s control node (ARM64 A2.Flex)
  ctrl_cloud_init_default = <<-CLOUDINIT
    #cloud-config
    # K3s control node bootstrap — minimal setup before Ansible
    hostname: ${local.name_prefix}-ctrl-01
    fqdn: ${local.name_prefix}-ctrl-01.demo.internal
    manage_etc_hosts: true

    disable_root: true

    growpart:
      mode: auto
      devices: ['/']
    resize_rootfs: true

    package_update: false
    package_upgrade: false

    packages:
      - chrony
      - firewalld
      - curl
      - python3
      - iscsi-initiator-utils

    runcmd:
      - systemctl enable --now chronyd
      - systemctl enable --now firewalld
      - chronyc makestep
      - timedatectl set-timezone UTC
      # Enable ip_tables modules required by K3s/Cilium
      - modprobe ip_tables
      - modprobe ip6_tables
      - modprobe xt_socket
      # Persist modules across reboots
      - echo "ip_tables" >> /etc/modules-load.d/k3s.conf
      - echo "ip6_tables" >> /etc/modules-load.d/k3s.conf
      - echo "xt_socket" >> /etc/modules-load.d/k3s.conf
      # K3s requires IPv4 forwarding
      - sysctl -w net.ipv4.ip_forward=1
      - echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/99-k3s.conf

    final_message: "K3s control node bootstrap complete after $UPTIME seconds"
    CLOUDINIT

  # Default cloud-init for K3s worker nodes (ARM64 A2.Flex)
  worker_cloud_init_default = <<-CLOUDINIT
    #cloud-config
    # K3s worker node bootstrap — minimal setup before Ansible
    hostname: ${local.name_prefix}-worker-PLACEHOLDER
    fqdn: ${local.name_prefix}-worker-PLACEHOLDER.demo.internal
    manage_etc_hosts: true

    disable_root: true

    growpart:
      mode: auto
      devices: ['/']
    resize_rootfs: true

    package_update: false
    package_upgrade: false

    packages:
      - chrony
      - firewalld
      - curl
      - python3
      - iscsi-initiator-utils

    runcmd:
      - systemctl enable --now chronyd
      - systemctl enable --now firewalld
      - chronyc makestep
      - timedatectl set-timezone UTC
      - modprobe ip_tables
      - modprobe ip6_tables
      - modprobe xt_socket
      - echo "ip_tables" >> /etc/modules-load.d/k3s.conf
      - echo "ip6_tables" >> /etc/modules-load.d/k3s.conf
      - echo "xt_socket" >> /etc/modules-load.d/k3s.conf
      - sysctl -w net.ipv4.ip_forward=1
      - echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/99-k3s.conf

    final_message: "K3s worker node bootstrap complete after $UPTIME seconds"
    CLOUDINIT

  # Default cloud-init for virtual workstation (ARM64 A2.Flex, DHCP)
  workstation_cloud_init_default = <<-CLOUDINIT
    #cloud-config
    # Virtual workstation bootstrap — minimal setup before Ansible
    hostname: ${local.name_prefix}-ws-01
    fqdn: ${local.name_prefix}-ws-01.demo.internal
    manage_etc_hosts: true

    disable_root: true

    growpart:
      mode: auto
      devices: ['/']
    resize_rootfs: true

    package_update: false
    package_upgrade: false

    packages:
      - chrony
      - firewalld
      - curl
      - python3

    runcmd:
      - systemctl enable --now chronyd
      - systemctl enable --now firewalld
      - chronyc makestep
      - timedatectl set-timezone UTC

    final_message: "Workstation bootstrap complete after $UPTIME seconds"
    CLOUDINIT
}
