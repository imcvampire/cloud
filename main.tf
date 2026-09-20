data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = var.ubuntu_version
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Cloudflare publishes its edge ranges as plaintext, one CIDR per line. Fetching
# them at plan time keeps the security list and AdGuard's trusted_proxies from
# drifting apart, which is what happens when both are maintained by hand.
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && length(compact([for l in split("\n", self.response_body) : trimspace(l)])) >= 10
      error_message = "Cloudflare IPv4 range list is unavailable or truncated. Refusing to apply a security list that would lock out every client."
    }
  }
}

data "http" "cloudflare_ipv6" {
  url = "https://www.cloudflare.com/ips-v6"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && length(compact([for l in split("\n", self.response_body) : trimspace(l)])) >= 5
      error_message = "Cloudflare IPv6 range list is unavailable or truncated. Refusing to apply a partial trusted-proxy list."
    }
  }
}

locals {
  availability_domain = coalesce(var.availability_domain, data.oci_identity_availability_domains.this.availability_domains[0].name)
  image_id            = data.oci_core_images.ubuntu.images[0].id

  cloudflare_ipv4 = compact([for l in split("\n", data.http.cloudflare_ipv4.response_body) : trimspace(l)])
  cloudflare_ipv6 = compact([for l in split("\n", data.http.cloudflare_ipv6.response_body) : trimspace(l)])

  # Cloudflare's reverse proxy carries HTTP and HTTPS only. TCP 853 cannot
  # traverse it on any standard plan, so DoT is governed by dot_cidrs instead.
  cloudflare_origin_ports = [80, 443]

  # The VCN is IPv4-only, so only v4 ranges become ingress rules. Both families
  # feed trusted_proxies, which reads forwarded headers rather than routing.
  cloudflare_trusted_proxies = join(" ", concat(local.cloudflare_ipv4, local.cloudflare_ipv6))
}

resource "oci_core_vcn" "adguard" {
  compartment_id = var.tenancy_ocid
  display_name   = "adguard-vcn"
  cidr_block     = "10.0.0.0/16"
  dns_label      = "adguard"
}

resource "oci_core_internet_gateway" "adguard" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adguard.id
  display_name   = "adguard-igw"
  enabled        = true
}

resource "oci_core_route_table" "adguard" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adguard.id
  display_name   = "adguard-public-routes"

  route_rules {
    network_entity_id = oci_core_internet_gateway.adguard.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "adguard" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adguard.id
  display_name   = "adguard-security-list"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # Attaching a custom list replaces OCI's default, which permits ICMP
  # type 3 code 4. Without it Path MTU Discovery breaks and TLS sessions
  # stall for clients behind reduced-MTU links.
  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  dynamic "ingress_security_rules" {
    for_each = toset(var.admin_cidrs)
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  # The initial setup dashboard is deliberately limited to administrator CIDRs.
  dynamic "ingress_security_rules" {
    for_each = toset(var.dashboard_cidrs)
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 3000
        max = 3000
      }
    }
  }

  # HTTP and HTTPS accept Cloudflare edge addresses only, so the origin is not
  # reachable directly and is not usable as an open resolver.
  dynamic "ingress_security_rules" {
    for_each = setproduct(local.cloudflare_ipv4, local.cloudflare_origin_ports)
    content {
      protocol = "6"
      source   = ingress_security_rules.value[0]
      tcp_options {
        min = ingress_security_rules.value[1]
        max = ingress_security_rules.value[1]
      }
    }
  }

  # DoT bypasses Cloudflare by necessity. Leaving dot_cidrs empty closes 853.
  dynamic "ingress_security_rules" {
    for_each = toset(var.dot_cidrs)
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 853
        max = 853
      }
    }
  }
}

resource "oci_core_subnet" "adguard" {
  compartment_id             = var.tenancy_ocid
  vcn_id                     = oci_core_vcn.adguard.id
  display_name               = "adguard-public-subnet"
  cidr_block                 = "10.0.0.0/24"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.adguard.id
  security_list_ids          = [oci_core_security_list.adguard.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_instance" "adguard" {
  availability_domain = local.availability_domain
  compartment_id      = var.tenancy_ocid
  display_name        = "amd64-1"
  shape               = var.instance_shape

  # Flexible shapes such as VM.Standard.A1.Flex require an explicit size;
  # fixed shapes such as VM.Standard.E2.1.Micro reject the block entirely.
  dynamic "shape_config" {
    for_each = var.instance_ocpus == null ? [] : [1]
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_gbs
    }
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.adguard.id
    assign_public_ip = true
    display_name     = "adguard-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = local.image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      timezone                = var.timezone
      adguard_update_calendar = var.adguard_update_calendar
      swap_size_bytes         = var.swap_size_gb * 1024 * 1024 * 1024
      adguard_memory_limit    = var.adguard_memory_limit
      cloudflare_ranges       = local.cloudflare_trusted_proxies
    }))
  }

  # OCI replaces an instance when its launch-time user_data changes. Keep
  # cloud-init fixes non-destructive for an already-running DNS server.
  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}
