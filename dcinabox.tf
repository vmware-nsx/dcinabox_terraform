terraform {
  required_providers {
    nsxt = {
      source = "vmware/nsxt"
    }
  }
}


provider "nsxt" {
  host                 = var.management_network["nsx_manager_ip"]
  username             = var.nsx["username"]
  password             = var.nsx["password"]
  on_demand_connection = true
  max_retries          = 10
  retry_min_delay      = 1000
  retry_max_delay      = 8000
  allow_unverified_ssl = true
}


provider "vsphere" {
  user                 = var.vcenter["username"]
  password             = var.vcenter["password"]
  vsphere_server       = var.vcenter["ip"]
  allow_unverified_ssl = true
  api_timeout          = 20
}

# ---------------------------------------------------------------------- #
#  vSphere Data Sources
# ---------------------------------------------------------------------- #


data "vsphere_datacenter" "datacenter" {
  name     = var.vcenter["dc"]
}


data "vsphere_compute_cluster" "cluster" {
  name          = var.vcenter["cluster"]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}


data "vsphere_host" "edge1_host" {
  name          = var.edge_nodes["edge1_host"]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_host" "edge2_host" {
  name          = var.edge_nodes["edge2_host"]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "edge1_datastore" {
  name          = var.edge_nodes["edge1_datastore"]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "edge2_datastore" {
  name          = var.edge_nodes["edge2_datastore"]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_distributed_virtual_switch" "vds" {
  name          = var.vcenter["vds"]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "mgmt_network" {
  name          = var.management_network["portgroup_name"]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# ---------------------------------------------------------------------- #
#  Compute manager
# ---------------------------------------------------------------------- #

resource "nsxt_compute_manager" "vcenter" {
  display_name = var.vcenter["fqdn"]
  server    = var.vcenter["ip"]
  multi_nsx = false
  credential {
    username_password_login {
      username   = var.vcenter["username"]
      password   = var.vcenter["password"]
      thumbprint = var.vcenter["thumbprint"]
    }
  }
}

data "nsxt_compute_manager_realization" "vcenter_realization" {
  id      = nsxt_compute_manager.vcenter.id
  timeout = 1200
}



# ----------------------------------------------- #
#  IP Pool
# ----------------------------------------------- #
resource "nsxt_policy_ip_pool" "tep_ip_pool" {
  display_name = "TEP_POOL"
}

data "nsxt_policy_realization_info" "tep_ip_pool" {
  path = nsxt_policy_ip_pool.tep_ip_pool.path
}

resource "nsxt_policy_ip_pool_static_subnet" "tep_ip_pool_range" {
  display_name = "range1"
  pool_path    = nsxt_policy_ip_pool.tep_ip_pool.path
  cidr         = "192.168.130.0/24"
  gateway      = "192.168.130.1"

  allocation_range {
    start = "192.168.130.2"
    end   = "192.168.130.254"
  }
}


# ----------------------------------------------- #
#  Uplink Profiles
# ----------------------------------------------- #

resource "nsxt_policy_uplink_host_switch_profile" "edge_uplink_profile" {
  display_name = "edge_uplink_profile"

  mtu            = 9000
  transport_vlan = var.overlay_vlan_id
  overlay_encap  = "GENEVE"

  teaming {
    active {
      uplink_name = "uplink2"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
  }

  named_teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
    name   = "uplink_1_only"
  }

  named_teaming {
    active {
      uplink_name = "uplink2"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
    name   = "uplink_2_only"
  }
}


resource "nsxt_policy_uplink_host_switch_profile" "esxi_uplink_profile" {
  display_name = "esxi_uplink_profile"

  transport_vlan = var.overlay_vlan_id
  overlay_encap  = "GENEVE"

  teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    active {
      uplink_name = "uplink2"
      uplink_type = "PNIC"
    }
    policy = "LOADBALANCE_SRCID"
  }

  named_teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    standby {
      uplink_name = "uplink2"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
    name   = "uplink_1_primary_uplink_2_secondary"
  }

  named_teaming {
    active {
      uplink_name = "uplink2"
      uplink_type = "PNIC"
    }
     standby {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
    name   = "uplink_2_primary_uplink_1_secondary"
  }
}

# ----------------------------------------------- #
#  Transport Zones
# ----------------------------------------------- #

data "nsxt_policy_transport_zone" "overlay_transport_zone" {
  display_name = "nsx-overlay-transportzone"
}

resource "nsxt_policy_transport_zone" "vlan_transport_zone_edge" {
  display_name   = "VLAN-EDGE"
  transport_type = "VLAN_BACKED"
  uplink_teaming_policy_names = ["uplink_1_only" , "uplink_2_only" ]
}


resource "nsxt_policy_transport_zone" "vlan_transport_zone_esxi" {
  display_name   = "VLAN-ESXI"
  transport_type = "VLAN_BACKED"
   uplink_teaming_policy_names = ["uplink_1_primary_uplink_2_secondary" , "uplink_2_primary_uplink_1_secondary"]
}

# ---------------------------------------------------------------------- #
#  Compute cluster preparation, create and apply TNP
# ---------------------------------------------------------------------- #


resource "nsxt_policy_host_transport_node_profile" "tnp" {
  display_name = "tnp"
  standard_host_switch {
    host_switch_id   = data.vsphere_distributed_virtual_switch.vds.id
    host_switch_mode = "STANDARD"
    ip_assignment {
      static_ip_pool = nsxt_policy_ip_pool.tep_ip_pool.path
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.path
    }
    transport_zone_endpoint {
      transport_zone = nsxt_policy_transport_zone.vlan_transport_zone_esxi.path
    }
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.esxi_uplink_profile.path]
    is_migrate_pnics    = false
    uplink {
      uplink_name     = "uplink1"
      vds_uplink_name = "Uplink 1"
    }
     uplink {
      uplink_name     = "uplink2"
      vds_uplink_name = "Uplink 2"
    }
  }
  depends_on = [data.nsxt_compute_manager_realization.vcenter_realization]
}

data "nsxt_compute_collection" "compute_cluster_collection" {
  display_name = data.vsphere_compute_cluster.cluster.name
  origin_id    = nsxt_compute_manager.vcenter.id
  depends_on = [data.nsxt_compute_manager_realization.vcenter_realization]
}

resource "nsxt_policy_host_transport_node_collection" "htnc1" {
  display_name                = "htnc1"
  compute_collection_id       = data.nsxt_compute_collection.compute_cluster_collection.id
  transport_node_profile_path = nsxt_policy_host_transport_node_profile.tnp.path
}


data "nsxt_policy_host_transport_node_collection_realization" "htnc1_realization" {
  id        = nsxt_policy_host_transport_node_collection.htnc1.id
  timeout   = 1200
  delay     = 1
}



# ------------------------------------------------------------------------------------------------------------ #
#  Create Edge segments, uplink segment will connect to fpath0 and overlay segment will connect to fpath1
# ------------------------------------------------------------------------------------------------------------ #


resource "nsxt_policy_segment" "dcinabox-trunk-uplink" {
  display_name        = "dcinabox-trunk-uplink"
  transport_zone_path = nsxt_policy_transport_zone.vlan_transport_zone_esxi.path
  vlan_ids = [var.uplink_vlan_id , var.management_vlan_id]
  advanced_config {
    uplink_teaming_policy = "uplink_1_primary_uplink_2_secondary"
  }
  depends_on = [data.nsxt_policy_host_transport_node_collection_realization.htnc1_realization]
}

resource "nsxt_policy_segment" "dcinabox-trunk-overlay" {
  display_name        = "dcinabox-trunk-overlay"
  transport_zone_path = nsxt_policy_transport_zone.vlan_transport_zone_esxi.path
  vlan_ids = [var.overlay_vlan_id , var.management_vlan_id]
  advanced_config {
    uplink_teaming_policy = "uplink_2_primary_uplink_1_secondary"
  }
  depends_on = [data.nsxt_policy_host_transport_node_collection_realization.htnc1_realization]
}


data "nsxt_policy_segment_realization" "dcinabox-trunk-uplink_realization" {
  path = nsxt_policy_segment.dcinabox-trunk-uplink.path
}

data "nsxt_policy_segment_realization" "dcinabox-trunk-overlay_realization" {
  path = nsxt_policy_segment.dcinabox-trunk-overlay.path
}



data "vsphere_network" "dcinabox-trunk-uplink" {
  name          = data.nsxt_policy_segment_realization.dcinabox-trunk-uplink_realization.network_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "dcinabox-trunk-overlay" {
  name          = data.nsxt_policy_segment_realization.dcinabox-trunk-overlay_realization.network_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}




# ---------------------------------------------------------------------- #
#  Edge Nodes
# ---------------------------------------------------------------------- #

resource "nsxt_edge_transport_node" "edgenode1" {
  description  = "Edge node 1"
  display_name = "edge-node1"
  standard_host_switch {
    ip_assignment {
      static_ip_pool = data.nsxt_policy_realization_info.tep_ip_pool.realized_id
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.id
    }
    transport_zone_endpoint {
      transport_zone = nsxt_policy_transport_zone.vlan_transport_zone_edge.realized_id
    }
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth0"
      uplink_name = "uplink1"
    }
    pnic {
      device_name = "fp-eth1"
      uplink_name = "uplink2"
    }
  }
  deployment_config {
    form_factor = "MEDIUM"
    node_user_settings {
      cli_password  = var.edge_nodes["password"]
      root_password = var.edge_nodes["password"]
    }
    vm_deployment_config {
      management_network_id = data.vsphere_network.mgmt_network.id
      data_network_ids      = [data.vsphere_network.dcinabox-trunk-uplink.id, data.vsphere_network.dcinabox-trunk-overlay.id ]
      compute_id            = data.vsphere_compute_cluster.cluster.id
      storage_id            = data.vsphere_datastore.edge1_datastore.id
      vc_id                 = nsxt_compute_manager.vcenter.id
      host_id               = data.vsphere_host.edge1_host.id
      management_port_subnet {
        ip_addresses  = [var.management_network["edge01_ip"]]
        prefix_length = var.management_network["prefix_length"]
      }
      default_gateway_address = [var.management_network["gateway_ip"]]
    }
  }
  node_settings {
    hostname             = "edge-node1"
    allow_ssh_root_login = true
    enable_ssh           = true
  }
}


resource "nsxt_edge_transport_node" "edgenode2" {
  description  = "Edge node 2"
  display_name = "edge-node2"
  standard_host_switch {
    ip_assignment {
      static_ip_pool = data.nsxt_policy_realization_info.tep_ip_pool.realized_id
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.id
    }
    transport_zone_endpoint {
      transport_zone = nsxt_policy_transport_zone.vlan_transport_zone_edge.realized_id
    }
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth0"
      uplink_name = "uplink1"
    }
    pnic {
      device_name = "fp-eth1"
      uplink_name = "uplink2"
    }
  }
  deployment_config {
    form_factor = var.edge_nodes["size"]
    node_user_settings {
      cli_password  = var.edge_nodes["password"]
      root_password = var.edge_nodes["password"]
    }
    vm_deployment_config {
      management_network_id = data.vsphere_network.mgmt_network.id
      data_network_ids      = [data.vsphere_network.dcinabox-trunk-uplink.id, data.vsphere_network.dcinabox-trunk-overlay.id]
      compute_id            = data.vsphere_compute_cluster.cluster.id
      storage_id            = data.vsphere_datastore.edge2_datastore.id
      vc_id                 = nsxt_compute_manager.vcenter.id
      host_id               = data.vsphere_host.edge2_host.id
      management_port_subnet {
        ip_addresses  = [var.management_network["edge02_ip"]]
        prefix_length = var.management_network["prefix_length"]
      }
      default_gateway_address = [var.management_network["gateway_ip"]]
    }
  }
  node_settings {
    hostname             = "edge-node2"
    allow_ssh_root_login = true
    enable_ssh           = true
  }
}

# ---------------------------------------------------------------------- #
#  Edge CLuster
# ---------------------------------------------------------------------- #


data "nsxt_transport_node_realization" "edgenode1_realization" {
  id      = nsxt_edge_transport_node.edgenode1.id
  timeout = 3000
}


data "nsxt_transport_node_realization" "edgenode2_realization" {
  id      = nsxt_edge_transport_node.edgenode2.id
  timeout = 3000
}


resource "nsxt_edge_cluster" "edgecluster1" {
  display_name = "Edge-cluster-01"
  member {
    transport_node_id = nsxt_edge_transport_node.edgenode1.id
  }
   member {
    transport_node_id = nsxt_edge_transport_node.edgenode2.id
  }
  depends_on         = [data.nsxt_transport_node_realization.edgenode1_realization,data.nsxt_transport_node_realization.edgenode2_realization]
}


# ---------------------------------------------------------------------- #
#  NSX Gateway (Tier-0)
# ---------------------------------------------------------------------- #

data "nsxt_policy_edge_cluster" "edgecluster1" {
  display_name = "Edge-cluster-01"
  depends_on         = [nsxt_edge_cluster.edgecluster1]
}

data "nsxt_policy_edge_node" "edgenode1" {
  edge_cluster_path = data.nsxt_policy_edge_cluster.edgecluster1.path
  display_name = "edge-node1"
}

data "nsxt_policy_edge_node" "edgenode2" {
  edge_cluster_path = data.nsxt_policy_edge_cluster.edgecluster1.path
  display_name = "edge-node2"
}

resource "nsxt_policy_tier0_gateway" "nsx-gateway" {
  display_name             = "nsx-gateway"
  nsx_id                   = "nsx-gateway"
  failover_mode            = "PREEMPTIVE"
  default_rule_logging     = false
  enable_firewall          = true
  ha_mode                  = "ACTIVE_STANDBY"
  edge_cluster_path        = data.nsxt_policy_edge_cluster.edgecluster1.path
}

# ---------------------------------------------------------------------- #
#  NSX-Gateway interfaces
# ---------------------------------------------------------------------- #

resource "nsxt_policy_segment" "edge-uplink" {
  display_name        = "edge-uplink"
  transport_zone_path = nsxt_policy_transport_zone.vlan_transport_zone_edge.path
  vlan_ids = [var.uplink_vlan_id]
  advanced_config {
    uplink_teaming_policy = "uplink_1_only"
  }
}

resource "nsxt_policy_segment" "edge-infra" {
  display_name        = "edge-infra"
  transport_zone_path = nsxt_policy_transport_zone.vlan_transport_zone_edge.path
  vlan_ids = [var.management_vlan_id]
  advanced_config {
    uplink_teaming_policy = "uplink_1_only"
  }
}

resource "nsxt_policy_tier0_gateway_interface" "uplink_edge1" {
  display_name   = "uplink-edge1"
  type           = "EXTERNAL"
  edge_node_path = data.nsxt_policy_edge_node.edgenode1.path
  gateway_path   = nsxt_policy_tier0_gateway.nsx-gateway.path
  segment_path   = nsxt_policy_segment.edge-uplink.path
  subnets        = [var.uplink_network["edge01_ip"]]
  mtu            = 1500
}

resource "nsxt_policy_tier0_gateway_interface" "uplink_edge2" {
  display_name   = "uplink-edge2"
  type           = "EXTERNAL"
  edge_node_path = data.nsxt_policy_edge_node.edgenode2.path
  gateway_path   = nsxt_policy_tier0_gateway.nsx-gateway.path
  segment_path   = nsxt_policy_segment.edge-uplink.path
  subnets        = [var.uplink_network["edge02_ip"]]
  mtu            = 1500
}

# ---------------------------------------------------------------------
#  NSX-Gateway Default Route
# ----------------------------------------------------------------------

resource "nsxt_policy_static_route" "default" {
  display_name = "default_route"
  gateway_path = nsxt_policy_tier0_gateway.nsx-gateway.path
  network      = "0.0.0.0/0"

  next_hop {
    ip_address     = var.uplink_network["gateway_ip"]
  }

}


# ---------------------------------------------------------------------- #
#  NSX-Gateway HA VIP
# ----------------------------------------------------------------------

resource "nsxt_policy_tier0_gateway_ha_vip_config" "ha-vip" {
  config {
    enabled                  = true
    external_interface_paths = [nsxt_policy_tier0_gateway_interface.uplink_edge1.path, nsxt_policy_tier0_gateway_interface.uplink_edge2.path]
    vip_subnets              = [var.uplink_network["vip_ip"]]
  }
}

# ---------------------------------------------------------------------- #
#  NSX-Gateway NAT
# ----------------------------------------------------------------------

resource "nsxt_policy_nat_rule" "SNAT_ALL" {
  display_name         = "Global SNAT"
  description          = "SNAT any outbound traffic"
  action               = "SNAT"
  translated_networks  = [var.uplink_network["snat_ip"]]
  gateway_path         = nsxt_policy_tier0_gateway.nsx-gateway.path
  logging              = false
  firewall_match       = "MATCH_INTERNAL_ADDRESS"
  rule_priority        = "1000"
  scope                = [nsxt_policy_tier0_gateway_interface.uplink_edge1.path, nsxt_policy_tier0_gateway_interface.uplink_edge2.path]
}


# ---------------------------------------------------------------------- #
#  Virtual Networks for workloads (DMZ and Internal)
# ----------------------------------------------------------------------

resource "nsxt_policy_segment" "dmz" {
  display_name        = "DMZ"
  connectivity_path   = nsxt_policy_tier0_gateway.nsx-gateway.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_transport_zone.path
  subnet {
    cidr        = "172.16.10.1/24"

  }
  tag {
    scope = "zone"
    tag   = "dmz"
  }
}

resource "nsxt_policy_segment" "internal" {
  display_name        = "INTERNAL"
  connectivity_path   = nsxt_policy_tier0_gateway.nsx-gateway.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_transport_zone.path
  subnet {
    cidr        = "172.16.20.1/24"

  }
  tag {
    scope = "zone"
    tag   = "internal"
  }
}

# ----------------------------------------------------------------------
#  Security Groups
# ----------------------------------------------------------------------

resource "nsxt_policy_group" "RDP-REMOTE-ACCESS" {
  display_name = "RDP-REMOTE-ACCESS"

  criteria {
    condition {
      key         = "Tag"
      member_type = "VirtualMachine"
      operator    = "EQUALS"
      value       = "remote|rdp"
    }
  }
}


resource "nsxt_policy_group" "SSH-REMOTE-ACCESS" {
  display_name = "SSH-REMOTE-ACCESS"

  criteria {
    condition {
      key         = "Tag"
      member_type = "VirtualMachine"
      operator    = "EQUALS"
      value       = "remote|ssh"
    }
  }
}


resource "nsxt_policy_group" "INTERNAL" {
  display_name = "INTERNAL"

  criteria {
    condition {
      key         = "Tag"
      member_type = "Segment"
      operator    = "EQUALS"
      value       = "zone|internal"
    }
  }
}


resource "nsxt_policy_group" "DMZ" {
  display_name = "DMZ"

  criteria {
    condition {
      key         = "Tag"
      member_type = "Segment"
      operator    = "EQUALS"
      value       = "zone|dmz"
    }
  }
}

# ----------------------------------------------------------------------
#  Security Services
# ----------------------------------------------------------------------

data "nsxt_policy_service" "rdp_service" {
  display_name = "RDP"
}

data "nsxt_policy_service" "ssh_service" {
  display_name = "SSH"
}

# ----------------------------------------------------------------------
#  DFW Policies
# ----------------------------------------------------------------------


resource "nsxt_policy_security_policy" "DMZ-ISOLATION" {
  display_name = "DMZ-ISOLATION"
  category     = "Application"
  locked       = false
  stateful     = true
  tcp_strict   = false
  scope        = [nsxt_policy_group.DMZ.path]

  rule {
    display_name       = "BlockDMZToInternal"
    source_groups      = [nsxt_policy_group.DMZ.path]
    destination_groups = [nsxt_policy_group.INTERNAL.path]
    action             = "DROP"
    logged             = true
    sequence_number    =  "1"
  }
  rule  {
    display_name       = "BlockDMZToDMZ"
    source_groups      = [nsxt_policy_group.DMZ.path]
    destination_groups = [nsxt_policy_group.DMZ.path]
    action             = "DROP"
    logged             = true
    sequence_number    =  "2"
  }
}

# ----------------------------------------------------------------------
#  GFW Policies
# ----------------------------------------------------------------------

resource "nsxt_policy_gateway_policy" "InboundPolicy" {
  display_name    = "InboundPolicy"
  category        = "LocalGatewayRules"
  locked          = false
  sequence_number = 100
  stateful        = true
  tcp_strict      = false

  rule {
    display_name       = "RDPAccess"
    destination_groups = [nsxt_policy_group.RDP-REMOTE-ACCESS.path]
    services           = [data.nsxt_policy_service.rdp_service.path]
    direction          = "IN"
    disabled           = false
    action             = "ALLOW"
    logged             = false
    sequence_number    = "100"
    scope              = [nsxt_policy_tier0_gateway.nsx-gateway.path]
  }

  rule {
    display_name       = "SSHAccess"
    destination_groups = [nsxt_policy_group.SSH-REMOTE-ACCESS.path]
    services           = [data.nsxt_policy_service.ssh_service.path]
    direction          = "IN"
    disabled           = false
    action             = "ALLOW"
    logged             = false
    sequence_number    = "200"
    scope              = [nsxt_policy_tier0_gateway.nsx-gateway.path]
  }

  rule {
    display_name       = "DenyInboundAll"
    direction          = "IN"
    disabled           = false
    action             = "DROP"
    logged             = true
    sequence_number    = "1000"
    scope              = [nsxt_policy_tier0_gateway.nsx-gateway.path]
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "nsxt_policy_gateway_policy" "OutboundPolicy" {
  display_name    = "OutboundPolicy"
  category        = "LocalGatewayRules"
  locked          = false
  sequence_number = 200
  stateful        = true
  tcp_strict      = false

  rule {
    display_name       = "AllowOutboundAll"
    direction          = "OUT"
    disabled           = false
    action             = "ALLOW"
    logged             = false
    sequence_number    = "100"
    scope              = [nsxt_policy_tier0_gateway.nsx-gateway.path]
  }

  lifecycle {
    create_before_destroy = true
  }
}
