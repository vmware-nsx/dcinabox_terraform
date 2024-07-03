terraform {
  required_providers {
    nsxt = {
      source = "vmware/nsxt"
    }
  }
}


provider "nsxt" {
  host                 = var.nsx["nsx_manager_ip"]
  username             = var.nsx["username"]
  password             = var.nsx["password"]
  on_demand_connection = true
  max_retries          = 10
  retry_min_delay      = 1000
  retry_max_delay      = 8000
  allow_unverified_ssl = true
}


# ---------------------------------------------------------------------- #
#  Compute manager
# ---------------------------------------------------------------------- #

data "external" "get_cm_thumbprint" {
  program = ["bash", "get_thumbprint.sh"]

  query = {
    server = "vcsa-01a.corp.local"
    port   = "443"
  }
}

output "cm_thumbprint" {
  value = data.external.get_cm_thumbprint.result.thumbprint
}

resource "nsxt_compute_manager" "vcenter" {
  display_name = var.vcenter["fqdn"]
  server    = var.vcenter["ip"]
  multi_nsx = false
  credential {
    username_password_login {
      username   = var.vcenter["username"]
      password   = var.vcenter["password"]
      thumbprint = data.external.get_cm_thumbprint.result.thumbprint
    }
  }
}

data "nsxt_compute_manager_realization" "vcenter_realization" {
  id      = nsxt_compute_manager.vcenter.id
  timeout = 1200
}
