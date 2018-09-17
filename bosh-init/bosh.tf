provider "openstack" {
  auth_url     = "${var.auth_url}"
  user_name    = "${var.user_name}"
  password     = "${var.password}"
  tenant_name  = "${var.tenant_name}"
  domain_name  = "${var.domain_name}"
  insecure     = "${var.insecure}"
  cacert_file = "${var.cacert_file}"
}

# access coordinates/credentials
variable "auth_url" {
  description = "Authentication endpoint URL for OpenStack provider (only scheme+host+port, but without path!)"
}

variable "user_name" {
  description = "OpenStack pipeline technical user name"
}

variable "password" {
  description = "OpenStack user password"
}

variable "tenant_name" {
  description = "OpenStack project/tenant name"
}

variable "domain_name" {
  description = "OpenStack domain name"
}

variable "insecure" {
  description = "Skip SSL verification"
  default = "false"
}

variable "cacert_file" {
  description = "Custom CA certificate"
  default = ""
}

# external network coordinates
variable "ext_net_name" {
  description = "OpenStack external network name to register floating IP"
}

# region/zone coordinates
variable "region_name" {
  description = "OpenStack region name"
}

variable "use_fuel_deploy" {
  default = "true"
}

#####

# input variables
variable "ext_net_id" {
  description = "OpenStack external network id to create router interface port"
}

variable "availability_zone" {
  description = "OpenStack availability zone name"
}

variable "dns_nameservers" {
  description = "Comma-separated list of DNS server IPs"
  default = "8.8.8.8"
}

# networks
resource "openstack_networking_network_v2" "mgmt" {
  count = "${var.use_fuel_deploy == "true" ? 0 : 1}"
  region         = "${var.region_name}"
  name           = "mgmt"
  admin_state_up = "true"

  provisioner "local-exec" {
    command = <<EOF
      echo net_id_mgmt: ${openstack_networking_network_v2.mgmt.id} >> ../deploy_vars
    EOF
  }
}

resource "openstack_networking_subnet_v2" "mgmt__subnet" {
  count = "${var.use_fuel_deploy == "true" ? 0 : 1}"
  region           = "${var.region_name}"
  network_id       = "${openstack_networking_network_v2.mgmt.id}"
  cidr             = "10.0.0.0/20"
  ip_version       = 4
  name             = "mgmt__subnet"
  allocation_pools = {
    start = "10.0.0.10"
    end   = "10.0.0.100"
  }
  gateway_ip       = "10.0.0.1"
  enable_dhcp      = "true"
  dns_nameservers  = ["${compact(split(",",var.dns_nameservers))}"]
}

# router
resource "openstack_networking_router_v2" "bosh_router" {
  count = "${var.use_fuel_deploy == "true" ? 0 : 1}"
  region           = "${var.region_name}"
  name             = "bosh-router"
  admin_state_up   = "true"
  external_network_id = "${var.ext_net_id}"

  provisioner "local-exec" {
    command = <<EOF
      echo bosh_router: ${openstack_networking_router_v2.bosh_router.id} >> ../deploy_vars
    EOF
  }
}

resource "openstack_networking_router_interface_v2" "bosh_port" {
  count = "${var.use_fuel_deploy == "true" ? 0 : 1}"
  region    = "${var.region_name}"
  router_id = "${openstack_networking_router_v2.bosh_router.id}"
  subnet_id = "${openstack_networking_subnet_v2.mgmt__subnet.id}"
}

#output "internal_cidr" {
#  value = "${openstack_networking_subnet_v2.mgmt__subnet.cidr}"
#}
#
#output "internal_gw" {
#  value = "${openstack_networking_subnet_v2.mgmt__subnet.gateway_ip}"
#}
#
#output "net_dns" {
#  value = "[${join(",", openstack_networking_subnet_v2.mgmt__subnet.dns_nameservers)}]"
#}
#
#output "net_id_mgmt" {
#  value = "${openstack_networking_network_v2.mgmt.id}"
#}
#
#output "internal_ip" {
#  value = "${cidrhost(openstack_networking_subnet_v2.mgmt__subnet.cidr, 10)}"
#}
#
#output "router_id" {
#  value = "${openstack_networking_router_v2.bosh_router.id}"
#}
#
#output "default_security_groups" {
#  value = "[${openstack_networking_secgroup_v2.secgroup.name}]"
#}

###

# input variables
# key pair
variable "keypair_suffix" {
  description = "Disambiguate keypairs with this suffix"
  default = ""
}


# security group
variable "security_group_suffix" {
  description = "Disambiguate security groups with this suffix"
  default = ""
}

# key pairs
resource "openstack_compute_keypair_v2" "bosh" {
  region     = "${var.region_name}"
  name       = "bosh${var.keypair_suffix}"
  public_key = "${replace("${file("bosh.pub")}","\n","")}"
}

# security group
resource "openstack_networking_secgroup_v2" "secgroup" {
  region = "${var.region_name}"
  name = "bosh${var.security_group_suffix}"
  description = "BOSH security group"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_self" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  remote_group_id = "${openstack_networking_secgroup_v2.secgroup.id}"
  security_group_id = "${openstack_networking_secgroup_v2.secgroup.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_22" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 22
  port_range_max = 22
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.secgroup.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_6868" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 6868
  port_range_max = 6868
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.secgroup.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_8443" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 8443
  port_range_max = 8443
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.secgroup.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_8844" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 8844
  port_range_max = 8844
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.secgroup.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_25555" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 25555
  port_range_max = 25555
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.secgroup.id}"
}

# floating ips
resource "openstack_networking_floatingip_v2" "cf_haproxy" {
  region = "${var.region_name}"
  pool   = "${var.ext_net_name}"
}

output "default_key_name" {
  value = "${openstack_compute_keypair_v2.bosh.name}"
}

output "cf_haproxy_external_ip" {
  value = "${openstack_networking_floatingip_v2.cf_haproxy.address}"
}
