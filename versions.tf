terraform {
  required_version = ">= 1.6.0"

  # Configure this empty block with `state.backend.hcl` after the bootstrap
  # bucket has been created. Keeping values out of source avoids committing
  # tenancy-specific backend details.
  backend "s3" {}

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
