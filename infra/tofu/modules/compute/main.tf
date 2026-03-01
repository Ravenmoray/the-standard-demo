# modules/compute/main.tf
# OCI compute instances for the it101 PoC.
#
# VM inventory:
#   it101-poc-edge-01   AMD Micro  DMZ subnet     x86_64   Public IP  Caddy edge
#   it101-poc-edge-02   AMD Micro  DMZ subnet     x86_64   Public IP  Caddy edge
#   it101-poc-ctrl-01   A2.Flex    APP subnet     aarch64  Private    K3s server
#   it101-poc-worker-01 A2.Flex    APP subnet     aarch64  Private    K3s agent
#   it101-poc-worker-02 A2.Flex    APP subnet     aarch64  Private    K3s agent
#   it101-poc-ws-01     A2.Flex    WORKSTATION    aarch64  Private    Workstation
#
# NOTE: A2.Flex is used for ARM instances, NOT A1.Flex.
# A1.Flex is chronically exhausted in us-chicago-1.
# A2.Flex uses trial/paid credits but has available capacity.

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

locals {
  ad_edge        = data.oci_identity_availability_domains.ads.availability_domains[var.ad_index_edge].name
  ad_k3s         = data.oci_identity_availability_domains.ads.availability_domains[var.ad_index_k3s].name
  ad_workstation = data.oci_identity_availability_domains.ads.availability_domains[var.ad_index_workstation].name
}

# ---------------------------------------------------------------------------
# Edge nodes — AMD Micro x86_64 in DMZ
# Two nodes for redundancy; Caddy TLS termination + reverse proxy
# ---------------------------------------------------------------------------

resource "oci_core_instance" "edge" {
  count = 2

  compartment_id      = var.compartment_id
  availability_domain = local.ad_edge
  display_name        = "${local.name_prefix}-edge-0${count.index + 1}"
  shape               = var.edge_shape

  # AMD Micro is a fixed shape — no flex config needed
  # (Attempting to set shape_config on a fixed shape will error)

  source_details {
    source_type             = "image"
    source_id               = var.image_id_ol9_x86
    boot_volume_size_in_gbs = var.edge_boot_volume_gb
  }

  create_vnic_details {
    subnet_id              = var.subnet_dmz_id
    display_name           = "${local.name_prefix}-edge-0${count.index + 1}-vnic"
    assign_public_ip       = var.assign_public_ip_to_edge
    hostname_label         = "${var.project_name}-${var.environment}-edge-0${count.index + 1}"
    skip_source_dest_check = false
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = var.edge_user_data != "" ? var.edge_user_data : base64encode(
      replace(local.edge_cloud_init_default, "PLACEHOLDER", "0${count.index + 1}")
    )
  }

  # Preserve boot volume on destroy (set to false for fully ephemeral PoC)
  preserve_boot_volume = false

  freeform_tags = merge(local.common_tags, {
    role        = "edge"
    k3s_role    = "none"
    node_index  = tostring(count.index + 1)
    arch        = "x86_64"
  })
}

# ---------------------------------------------------------------------------
# K3s Control node — A2.Flex ARM64 in APP subnet
# ---------------------------------------------------------------------------

resource "oci_core_instance" "ctrl" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad_k3s
  display_name        = "${local.name_prefix}-ctrl-01"
  shape               = var.ctrl_shape

  shape_config {
    ocpus         = var.ctrl_ocpus
    memory_in_gbs = var.ctrl_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id_ol9_arm64
    boot_volume_size_in_gbs = var.ctrl_boot_volume_gb
  }

  create_vnic_details {
    subnet_id              = var.subnet_app_id
    display_name           = "${local.name_prefix}-ctrl-01-vnic"
    assign_public_ip       = false # Private subnet; access via WireGuard VPN
    hostname_label         = "${var.project_name}-${var.environment}-ctrl-01"
    skip_source_dest_check = true # Required for K3s/Cilium traffic forwarding
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = var.ctrl_user_data != "" ? var.ctrl_user_data : base64encode(
      local.ctrl_cloud_init_default
    )
  }

  preserve_boot_volume = false

  freeform_tags = merge(local.common_tags, {
    role       = "k3s-control"
    k3s_role   = "server"
    arch       = "aarch64"
  })
}

# ---------------------------------------------------------------------------
# K3s Worker nodes — A2.Flex ARM64 in APP subnet (x2)
# ---------------------------------------------------------------------------

resource "oci_core_instance" "worker" {
  count = 2

  compartment_id      = var.compartment_id
  availability_domain = local.ad_k3s
  display_name        = "${local.name_prefix}-worker-0${count.index + 1}"
  shape               = var.worker_shape

  shape_config {
    ocpus         = var.worker_ocpus
    memory_in_gbs = var.worker_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id_ol9_arm64
    boot_volume_size_in_gbs = var.worker_boot_volume_gb
  }

  create_vnic_details {
    subnet_id              = var.subnet_app_id
    display_name           = "${local.name_prefix}-worker-0${count.index + 1}-vnic"
    assign_public_ip       = false
    hostname_label         = "${var.project_name}-${var.environment}-worker-0${count.index + 1}"
    skip_source_dest_check = true # Required for K3s/Cilium traffic forwarding
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = var.worker_user_data != "" ? var.worker_user_data : base64encode(
      replace(local.worker_cloud_init_default, "PLACEHOLDER", "0${count.index + 1}")
    )
  }

  preserve_boot_volume = false

  freeform_tags = merge(local.common_tags, {
    role       = "k3s-worker"
    k3s_role   = "agent"
    node_index = tostring(count.index + 1)
    arch       = "aarch64"
  })
}

# ---------------------------------------------------------------------------
# Virtual Workstation — A2.Flex ARM64 in WORKSTATION subnet
# DHCP assignment; no public IP; access via SSH from MANAGEMENT subnet
# ---------------------------------------------------------------------------

resource "oci_core_instance" "workstation" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad_workstation
  display_name        = "${local.name_prefix}-ws-01"
  shape               = var.workstation_shape

  shape_config {
    ocpus         = var.workstation_ocpus
    memory_in_gbs = var.workstation_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id_ol9_arm64
    boot_volume_size_in_gbs = var.workstation_boot_volume_gb
  }

  create_vnic_details {
    subnet_id        = var.subnet_workstation_id
    display_name     = "${local.name_prefix}-ws-01-vnic"
    assign_public_ip = false # WORKSTATION subnet is private; access via management
    # hostname_label is intentionally omitted here to rely on DHCP assignment
    skip_source_dest_check = false
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = var.workstation_user_data != "" ? var.workstation_user_data : base64encode(
      local.workstation_cloud_init_default
    )
  }

  preserve_boot_volume = false

  freeform_tags = merge(local.common_tags, {
    role = "workstation"
    arch = "aarch64"
    dhcp = "true"
  })
}
