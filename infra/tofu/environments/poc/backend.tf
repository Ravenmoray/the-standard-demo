# environments/poc/backend.tf
# OpenTofu remote state backend configuration — OCI Object Storage.
#
# =============================================================================
# BOOTSTRAP PROCEDURE (chicken-and-egg)
# =============================================================================
#
# The remote state bucket must exist BEFORE running 'tofu init'.
# This file references the bucket but cannot create it.
#
# Step 1: Create the state bucket manually via OCI CLI:
#
#   export NAMESPACE=$(oci os ns get --query 'data' --raw-output)
#   export COMPARTMENT_ID="<your-compartment-ocid>"
#   export BUCKET_NAME="it101-poc-tofu-state"
#
#   oci os bucket create \
#     --compartment-id "$COMPARTMENT_ID" \
#     --namespace "$NAMESPACE" \
#     --name "$BUCKET_NAME" \
#     --versioning Enabled \
#     --public-access-type NoPublicAccess
#
# Step 2: Create an OCI pre-authenticated request (PAR) for the bucket
#         OR configure OCI API key auth for the S3-compatible endpoint.
#         The S3-compatible endpoint is:
#           https://<NAMESPACE>.compat.objectstorage.<REGION>.oraclecloud.com
#
# Step 3: Fill in the values below and run:
#
#   tofu init \
#     -backend-config="access_key=<YOUR_ACCESS_KEY>" \
#     -backend-config="secret_key=<YOUR_SECRET_KEY>"
#
#   # Or create a .s3.tfbackend file (gitignored) with:
#   # access_key = "..."
#   # secret_key = "..."
#   # and run: tofu init -backend-config=.s3.tfbackend
#
# Step 4: Run 'tofu plan' and 'tofu apply' — OpenTofu will manage all
#         subsequent infrastructure from this remote state.
#
# Step 5: After first apply, the state bucket is also managed as a resource
#         (oci_objectstorage_bucket.state in modules/network).
#         If 'tofu destroy' is ever run, it will attempt to delete the bucket.
#         Protect against this by enabling versioning and bucket retention rules.
#
# =============================================================================
# ACCESS KEY GENERATION
# =============================================================================
#
# OCI Object Storage presents an S3-compatible API. Access keys are
# Customer Secret Keys tied to an IAM user (not an API key).
#
#   oci iam customer-secret-key create \
#     --user-id <USER_OCID> \
#     --display-name "opentofu-state-key"
#
# Store the generated secret_key immediately — it is shown only once.
# Store both keys in your password manager or Ansible Vault.
# =============================================================================

terraform {
  backend "s3" {
    # OCI Object Storage S3-compatible endpoint
    # Replace <NAMESPACE> and <REGION> with actual values
    endpoint = "https://<NAMESPACE>.compat.objectstorage.us-chicago-1.oraclecloud.com"
    region   = "us-chicago-1"

    bucket = "it101-poc-tofu-state"
    key    = "environments/poc/terraform.tfstate"

    # OCI does not support native S3 bucket versioning checks via this API
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id = true

    # Force path-style (required for OCI S3 compatibility)
    force_path_style = true

    # access_key and secret_key are provided via:
    #   - Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
    #   - -backend-config flags at 'tofu init' time
    #   - A .s3.tfbackend file (add to .gitignore)
    # DO NOT hardcode credentials here.
  }
}
