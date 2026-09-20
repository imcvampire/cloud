variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key_path" {
  type = string
}

variable "region" {
  type = string
}

variable "state_bucket_name" {
  description = "Globally unique within this OCI tenancy's Object Storage namespace."
  type        = string
  default     = "tofu-state"
}
