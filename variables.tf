variable "vcenter" {
  type = map(string)
  default = {
    fqdn       = "vcsa-01a.corp.local"
    ip         = "192.168.110.22"
    username   = "administrator@vsphere.local"
    password   = "VMware1!"
    thumbprint = "24:84:94:F1:88:8E:7C:43:B3:A9:77:1F:FB:44:6F:F6:D9:5F:46:D9:78:51:AE:61:D4:EB:18:81:FF:A4:61:8E"
    dc         = "Site-A"
    cluster    = "Cluster-02a"
    vds        = "SiteA-vDS-02"
  }
}

variable "nsx" {
  type = map(string)
  default = {
    username = "admin"
    password = "VMware1!VMware1!"
  }
}

variable "uplink_vlan_id" {
  type    = string
  default = "100"
}

variable "overlay_vlan_id" {
  type    = string
  default = "130"
}

variable "management_vlan_id" {
  type    = string
  default = "200"
}

variable "uplink_network" {
  type = map(string)
  default = {
    snat_ip       = "192.168.254.6"
    vip_ip        = "192.168.254.5/24"
    edge01_ip     = "192.168.254.1/24"
    edge02_ip     = "192.168.254.2/24"
    gateway_ip    = "192.168.254.3"
  }
}

variable "management_network" {
  type = map(any)
  default = {
    prefix_length                   = 24
    gateway_ip                      = "192.168.110.1"
    nsx_manager_ip                  = "192.168.110.15"
    edge01_ip                       = "192.168.110.19"
    edge02_ip                       = "192.168.110.20"
    portgroup_name                  = "SiteA-vDS-02-Mgmt"
    nsxgateway_serviceinterface_present = "False"
    nsxgateway_serviceinterface_ip  = "192.168.100.1"
  }
}

variable "edge_nodes" {
  type = map(any)
  default = {
    size             = "MEDIUM"
    edge1_datastore  = "nfs-02"
    edge1_host       = "esx-03a.corp.local"
    edge2_datastore  = "nfs-02"
    edge2_host       = "esx-04a.corp.local"
    password         = "VMware1!VMware1!"
    dns_server      = "192.168.110.10"
  }
}
