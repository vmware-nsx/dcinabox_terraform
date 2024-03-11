# dcinabox_terraform

This repository provides Terraform configuration files to automate the deployment of the Datacenter in a Box solution described in the [NSX Easy Adotion Design Guide Document](https://communities.vmware.com/t5/VMware-NSX-Documents/NSX-Easy-Adoption-Design-Guide/ta-p/2936898]). Running the automation requires a machine with Terraform installed. This branch requires using the NSX Terraform provider v3.6.0 available at [link](https://github.com/vmware/terraform-provider-nsxt)

___
## Applicable versions
1) NSX 4.1.x
2) NSX Terrafrom provider 3.6.0


## DC in a Box deployment steps
1)	Deploy the NSX Manager OVA via the vSphere Client
2)	Check that the NSX Manager GUI is accessible and install the license
3)	Download the terraform configuration files from this repo
4)	Customize the variables.tf file based on your environment
5)	Run terraform init, then terraform apply
