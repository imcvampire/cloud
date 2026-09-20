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

variable "dot_cidrs" {
  description = "CIDRs allowed to reach DoT on TCP 853. Cloudflare's proxy cannot carry 853, so this bypasses Cloudflare and reaches the origin directly. Empty closes the port."
  type        = list(string)
  default     = []
}

variable "dns_hostname" {
  description = "Cloudflare-proxied hostname clients use for DoH, for example dns.example.com. Required for usable endpoint outputs; the origin IP is not reachable for DoH once ingress is limited to Cloudflare."
  type        = string
  default     = null
}


variable "instance_shape" {
  description = "Always Free eligible shape. VM.Standard.E2.1.Micro is 1/8 OCPU and 1 GB; VM.Standard.A1.Flex is arm64 and needs instance_ocpus and instance_memory_gbs set."
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "instance_ocpus" {
  description = "OCPUs for a flexible shape. Leave null for fixed shapes such as VM.Standard.E2.1.Micro, which reject a shape_config block."
  type        = number
  default     = null
}

variable "instance_memory_gbs" {
  description = "Memory for a flexible shape, in GB. Ignored unless instance_ocpus is set."
  type        = number
  default     = null
}

variable "swap_size_gb" {
  description = "Swap file size. Absorbs the allocation burst from apt and container image pulls, which is what exhausts a 1 GB host."
  type        = number
  default     = 2
}

variable "adguard_memory_limit" {
  description = "Hard memory ceiling for the AdGuard container, so it cannot take the host down with it."
  type        = string
  default     = "512m"
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
