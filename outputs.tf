output "public_ip" {
  description = "Public address of the AdGuard Home server."
  value       = oci_core_instance.adguard.public_ip
}

output "setup_dashboard" {
  description = "Initial AdGuard Home setup URL; reachable only from admin_cidrs."
  value       = "http://${oci_core_instance.adguard.public_ip}:3000"
}

output "doh_endpoint" {
  description = "After TLS is configured in AdGuard Home, use this endpoint."
  value       = "https://${oci_core_instance.adguard.public_ip}/dns-query"
}

output "dot_endpoint" {
  description = "After TLS is configured in AdGuard Home, use this hostname and port 853."
  value       = "${oci_core_instance.adguard.public_ip}:853"
}
