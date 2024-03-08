variable "vcenter" {
  type = map(string)
  default = {
    fqdn       = "vcsa-01a.corp.local"
    ip         = "192.168.110.22"
    username   = "administrator@vsphere.local"
    password   = "VMware1!"
    thumbprint = "98:90:91:93:45:24:D0:10:A4:02:CF:E9:DA:54:24:D2:C6:27:F2:91:AF:AF:87:8A:DB:96:79:C3:FE:39:3E:10"
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
