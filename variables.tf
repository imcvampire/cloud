variable "tenancy_ocid" {
  description = "Oracle Cloud tenancy OCID."
  type        = string
}

variable "user_ocid" {
  description = "OCI API user OCID."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API signing key."
  type        = string
}

variable "private_key_path" {
  description = "Absolute path to the OCI API signing private key."
  type        = string
}

variable "region" {
  description = "OCI region, for example eu-frankfurt-1."
  type        = string
}

variable "availability_domain" {
  description = "Optional availability domain name. Leave null to select the first one."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key allowed to administer the instance."
  type        = string
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach SSH."
  type        = list(string)
}

variable "dashboard_cidrs" {
  description = "CIDRs allowed to reach the AdGuard Home setup dashboard. Restrict this to your public IP."
  type        = list(string)
}

variable "dns_cidrs" {
  description = "CIDRs allowed to use DNS, DoH, and DoT. 0.0.0.0/0 makes this a public resolver."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_shape" {
  description = "Always Free eligible AMD64 shape."
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "ubuntu_version" {
  description = "Canonical Ubuntu image version to use."
  type        = string
  default     = "24.04"
}

variable "timezone" {
  description = "IANA timezone used by the update schedule."
  type        = string
  default     = "Etc/UTC"
}

variable "adguard_update_calendar" {
  description = "systemd OnCalendar expression for AdGuard Home updates. Defaults to 04:00 daily."
  type        = string
  default     = "*-*-* 04:00:00"
}

variable "state_bucket_name" {
  description = "Name used by the separate bootstrap configuration to create the remote-state bucket."
  type        = string
  default     = "tofu-state"
}
