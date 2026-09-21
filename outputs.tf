output "public_ip" {
  description = "Origin address of the AdGuard Home server. Point the Cloudflare proxied record at this."
  value       = oci_core_instance.adguard.public_ip
}

output "setup_dashboard" {
  description = "Initial AdGuard Home setup URL; reachable only from dashboard_cidrs, bypassing Cloudflare."
  value       = "http://${oci_core_instance.adguard.public_ip}:3000"
}

output "doh_endpoint" {
  description = "DoH endpoint. Resolves through Cloudflare; the origin IP no longer accepts direct DoH."
  value       = var.dns_hostname == null ? "Set dns_hostname. Ingress on 443 is limited to Cloudflare, so DoH is unreachable at the origin IP." : "https://${var.dns_hostname}/dns-query"
}

output "dot_endpoint" {
  description = "DoT endpoint. Bypasses Cloudflare and hits the origin directly, so it requires dot_cidrs to be non-empty."
  value       = length(var.dot_cidrs) == 0 ? "Closed. TCP 853 cannot traverse Cloudflare's proxy; set dot_cidrs to open it directly to the origin." : "${coalesce(var.dns_hostname, oci_core_instance.adguard.public_ip)}:853"
}

output "cloudflare_ranges_applied" {
  description = "Count of Cloudflare edge ranges in the security list at last apply. A change here means the upstream list moved."
  value       = "${length(local.cloudflare_ipv4)} IPv4 ingress ranges, ${length(local.cloudflare_ipv6)} IPv6 ranges in trusted_proxies"
}

output "arm64_public_ip" {
  description = "Public address of arm64-1, or null when create_arm64 is false."
  value       = one(oci_core_instance.arm64[*].public_ip)
}

output "arm64_ssh" {
  description = "SSH command for arm64-1. Reachable only from admin_cidrs."
  value       = var.create_arm64 ? "ssh ubuntu@${one(oci_core_instance.arm64[*].public_ip)}" : "Not created. Set create_arm64 = true to build it."
}
