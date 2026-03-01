# modules/object-storage/main.tf
# Standalone Object Storage module.
#
# This module is available for use cases where Object Storage buckets
# need to be managed independently of the network module (e.g., creating
# additional application-specific buckets in later deployment phases).
#
# The three core buckets (state, loki, backup) are managed by the
# network module to keep them in the same state file as the VCN.
# Use this module for additional buckets (e.g., Nextcloud overflow,
# Grafana Tempo traces, additional backups).

locals {
  common_tags = merge(var.tags, {
    project     = var.project_name
    environment = var.environment
    managed_by  = "opentofu"
  })
}

resource "oci_objectstorage_bucket" "this" {
  for_each = var.buckets

  compartment_id = var.compartment_id
  namespace      = var.object_storage_namespace
  name           = each.value.name
  access_type    = "NoPublicAccess"
  versioning     = each.value.versioning_enabled ? "Enabled" : "Disabled"

  metadata = {
    purpose     = each.value.purpose
    environment = var.environment
    managed_by  = "opentofu"
  }

  freeform_tags = merge(local.common_tags, {
    bucket_purpose = each.value.purpose
  })
}
