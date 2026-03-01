# modules/network/object_storage.tf
# OCI Object Storage buckets provisioned alongside the network.
#
# Three buckets:
#   state   – OpenTofu remote state (versioned, private)
#   loki    – Loki log chunk storage (private)
#   backup  – Restic/Velero backup target (private)
#
# BOOTSTRAP NOTE: The state bucket (${state_bucket_name}) has a chicken-and-egg
# problem — it must exist before 'tofu init' can configure the remote backend.
# Bootstrap procedure:
#
#   1. Create the state bucket manually via OCI Console or CLI:
#        oci os bucket create \
#          --compartment-id <COMPARTMENT_OCID> \
#          --namespace <NAMESPACE> \
#          --name <STATE_BUCKET_NAME> \
#          --versioning Enabled \
#          --public-access-type NoPublicAccess
#
#   2. Configure backend.tf with the bucket name (see environments/poc/backend.tf).
#
#   3. Run 'tofu init' to initialise the remote backend.
#
#   4. Run 'tofu apply' — OpenTofu will then manage this bucket as a resource
#      in the state it just created (import if necessary).
#
# After bootstrap, all three buckets are managed via this module.

resource "oci_objectstorage_bucket" "state" {
  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = var.state_bucket_name
  access_type    = "NoPublicAccess"

  # Versioning is critical for state bucket — allows recovery from corruption
  versioning = "Enabled"

  # Prevent accidental destruction; the state bucket holds the blast radius
  # for all infra. Disable this only intentionally.
  # Note: OpenTofu does not support lifecycle prevent_destroy on modules;
  # add prevent_destroy = true in a wrapper if needed.

  metadata = {
    purpose     = "opentofu-remote-state"
    environment = var.environment
    managed_by  = "opentofu"
  }

  freeform_tags = merge(local.common_tags, {
    bucket_purpose = "opentofu-state"
  })
}

resource "oci_objectstorage_bucket" "loki" {
  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = var.loki_bucket_name
  access_type    = "NoPublicAccess"
  versioning     = "Disabled"

  metadata = {
    purpose     = "loki-log-chunks"
    environment = var.environment
    managed_by  = "opentofu"
  }

  freeform_tags = merge(local.common_tags, {
    bucket_purpose = "loki-chunks"
  })
}

resource "oci_objectstorage_bucket" "backup" {
  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = var.backup_bucket_name
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"

  metadata = {
    purpose     = "restic-velero-backup"
    environment = var.environment
    managed_by  = "opentofu"
  }

  freeform_tags = merge(local.common_tags, {
    bucket_purpose = "backup"
  })
}
