# modules/object-storage/outputs.tf

output "bucket_names" {
  description = "Map of logical bucket key to OCI bucket name."
  value       = { for k, b in oci_objectstorage_bucket.this : k => b.name }
}

output "bucket_ids" {
  description = "Map of logical bucket key to bucket OCID."
  value       = { for k, b in oci_objectstorage_bucket.this : k => b.id }
}
