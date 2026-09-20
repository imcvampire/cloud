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

locals {
  availability_domain = coalesce(var.availability_domain, data.oci_identity_availability_domains.this.availability_domains[0].name)
  image_id            = data.oci_core_images.ubuntu.images[0].id
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

  dynamic "ingress_security_rules" {
    for_each = toset(var.dns_cidrs)
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      # Needed when AdGuard Home obtains/renews a Let's Encrypt certificate.
      tcp_options {
        min = 80
        max = 80
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = toset(var.dns_cidrs)
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = toset(var.dns_cidrs)
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
    }))
  }

  # OCI replaces an instance when its launch-time user_data changes. Keep
  # cloud-init fixes non-destructive for an already-running DNS server.
  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}
