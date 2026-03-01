# modules/object-storage/variables.tf

variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID."
}

variable "object_storage_namespace" {
  type        = string
  description = "OCI Object Storage namespace."
}

variable "project_name" {
  type        = string
  description = "Project identifier used in tags."
  default     = "it101"
}

variable "environment" {
  type        = string
  description = "Environment label."
  default     = "poc"
}

variable "buckets" {
  type = map(object({
    name                = string
    purpose             = string
    versioning_enabled  = bool
  }))
  description = "Map of bucket configurations. Key is a logical name; value contains OCI bucket properties."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Freeform tags applied to all buckets."
  default     = {}
}
