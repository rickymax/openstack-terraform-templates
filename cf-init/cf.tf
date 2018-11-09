provider "openstack" {
  auth_url    = "${var.auth_url}"
  user_name   = "${var.user_name}"
  password    = "${var.password}"
  tenant_name = "${var.project_name}"
  domain_name = "${var.domain_name}"
  insecure    = "${var.insecure}"
  cacert_file = "${var.cacert_file}"
}

variable "auth_url" {
  description = "Authentication endpoint URL for OpenStack provider (only scheme+host+port, but without path!)"
}

variable "domain_name" {
  description = "OpenStack domain name"
}

variable "user_name" {
  description = "OpenStack pipeline technical user name"
}

variable "password" {
  description = "OpenStack user password"
}

variable "project_name" {
  description = "OpenStack project/tenant name"
}

variable "insecure" {
  default = "false"
  description = "SSL certificate validation"
}

variable "cacert_file" {
  default = ""
  description = "Path to trusted CA certificate for OpenStack in PEM format"
}

variable "region_name" {
  description = "OpenStack region name"
}

variable "dns_nameservers" {
  type    = "list"
  description = "DNS server IPs"
}

variable "availability_zones" {
  type = "list"
}

variable "ext_net_name" {
  description = "OpenStack external network name to register floating IP"
}

variable "bosh_router_id" {
  description = "ID of the router, which has an interface to the BOSH network"
}

resource "openstack_networking_network_v2" "cf_net" {
  count          = "${length(var.availability_zones)}"
  region         = "${var.region_name}"
  name           = "cf${count.index+1}"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "cf__subnet" {
  count          = "${length(var.availability_zones)}"
  region           = "${var.region_name}"
  network_id       = "${element(openstack_networking_network_v2.cf_net.*.id, count.index)}"
  cidr             = "${cidrsubnet("10.0.0.0/16", 4, count.index+1)}"
  ip_version       = 4
  name           = "cf${count.index+1}__subnet"
  allocation_pools = {
    start = "${cidrhost(cidrsubnet("10.0.0.0/16", 4, count.index+1), 10)}"
    end   = "${cidrhost(cidrsubnet("10.0.0.0/16", 4, count.index+1), 100)}"
  }
  gateway_ip       = "${cidrhost(cidrsubnet("10.0.0.0/16", 4, count.index+1), 1)}"
  enable_dhcp      = "true"
  dns_nameservers = "${var.dns_nameservers}"
}

resource "openstack_networking_network_v2" "db_net" {
  region         = "${var.region_name}"
  name           = "db-service"
  admin_state_up = "true"

  provisioner "local-exec" {
    command = <<EOF
      echo net_id_cf1: ${openstack_networking_network_v2.cf_net.0.id} >> ../terraform-vars.yml
      echo net_id_cf2: ${openstack_networking_network_v2.cf_net.1.id} >> ../terraform-vars.yml
      echo net_id_cf3: ${openstack_networking_network_v2.cf_net.2.id} >> ../terraform-vars.yml
      echo net_id_db: ${openstack_networking_network_v2.db_net.id} >> ../terraform-vars.yml
    EOF
  }
}

resource "openstack_networking_subnet_v2" "db__subnet" {
  region           = "${var.region_name}"
  network_id       = "${openstack_networking_network_v2.db_net.id}"
  cidr             = "10.100.0.0/16"
  ip_version       = 4
  name             = "db__subnet"
  allocation_pools = {
    start = "10.100.0.2"
    end   = "10.100.255.254"
  }
  gateway_ip       = "10.100.0.1"
  enable_dhcp      = "true"
  dns_nameservers  = "${var.dns_nameservers}"
}

resource "openstack_networking_network_v2" "rmq_net" {
  region         = "${var.region_name}"
  name           = "rabbitmq-service"
  admin_state_up = "true"

  provisioner "local-exec" {
    command = <<EOF
      echo net_id_rmq: ${openstack_networking_network_v2.rmq_net.id} >> ../terraform-vars.yml
    EOF
  }
}

resource "openstack_networking_subnet_v2" "rmq__subnet" {
  region           = "${var.region_name}"
  network_id       = "${openstack_networking_network_v2.rmq_net.id}"
  cidr             = "10.10.0.0/16"
  ip_version       = 4
  name             = "rabbitmq__subnet"
  allocation_pools = {
    start = "10.10.0.2"
    end   = "10.10.255.254"
  }
  gateway_ip       = "10.10.0.1"
  enable_dhcp      = "true"
  dns_nameservers  = "${var.dns_nameservers}"
}

resource "openstack_networking_secgroup_v2" "wise_sec_group" {
  region      = "${var.region_name}"
  name        = "WISE-PaaS-nsg"
  description = "WISE-PaaS security group"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_udp" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "udp"
  remote_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
  region = "${var.region_name}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_icmp" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "icmp"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
  region = "${var.region_name}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_self" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  remote_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
  region = "${var.region_name}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_22" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 22
  port_range_max = 22
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_80" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 80
  port_range_max = 80
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_443" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 443
  port_range_max = 443
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_1883" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 1883
  port_range_max = 1883
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_3000" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 3000
  port_range_max = 3000
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_4222" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 4222
  port_range_max = 4222
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_4443" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 4443
  port_range_max = 4443
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_5432" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 5432
  port_range_max = 5432
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_5671" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 5671
  port_range_max = 5671
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_5672" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 5672
  port_range_max = 5672
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_6379" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 6379
  port_range_max = 6379
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_6380" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 6380
  port_range_max = 6380
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_8086" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 8086
  port_range_max = 8086
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_8883" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 8883
  port_range_max = 8883
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_9090" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 9090
  port_range_max = 9090
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_9093" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 9093
  port_range_max = 9093
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_15672" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 15672
  port_range_max = 15672
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_27017" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 27017
  port_range_max = 27017
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_tcp_25777" {
  region = "${var.region_name}"
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 25777
  port_range_max = 25777
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.wise_sec_group.id}"
}

resource "openstack_networking_router_interface_v2" "cf_router_interface" {
  count = "${length(var.availability_zones)}"
  router_id = "${var.bosh_router_id}"
  subnet_id = "${element(openstack_networking_subnet_v2.cf__subnet.*.id, count.index)}"
  region = "${var.region_name}"
}

resource "openstack_networking_router_interface_v2" "db_router_interface" {
  router_id = "${var.bosh_router_id}"
  subnet_id = "${openstack_networking_subnet_v2.db__subnet.id}"
  region = "${var.region_name}"
}

resource "openstack_networking_router_interface_v2" "rmq_router_interface" {
  router_id = "${var.bosh_router_id}"
  subnet_id = "${openstack_networking_subnet_v2.rmq__subnet.id}"
  region = "${var.region_name}"
}

output "net_id_cf" {
  value = "${openstack_networking_network_v2.cf_net.*.id}"
}

output "net_id_rmq" {
  value = "${openstack_networking_network_v2.rmq_net.id}"
}

output "net_id_db" {
  value = "${openstack_networking_network_v2.db_net.id}"
}

output "security group to be assigned to BOSH vm" {
  value = "${openstack_networking_secgroup_v2.wise_sec_group.name}"
}

# flavor
# note: attributes such as ephemeral and "extra" fields are not yet supported
resource "openstack_compute_flavor_v2" "minimal-lowmem" {
  name  = "minimal-lowmem"
  ram   = "2048"
  vcpus = "1"
  disk  = "13"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "minimal" {
  name  = "minimal"
  ram   = "4096"
  vcpus = "1"
  disk  = "13"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "small-lowmem" {
  name  = "small-lowmem"
  ram   = "4096"
  vcpus = "2"
  disk  = "13"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "small" {
  name  = "small"
  ram   = "8192"
  vcpus = "2"
  disk  = "19"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "small-highmem" {
  name  = "small-highmem"
  ram   = "16384"
  vcpus = "2"
  disk  = "35"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "medium-lowmem" {
  name  = "medium-lowmem"
  ram   = "8192"
  vcpus = "4"
  disk  = "19"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "medium" {
  name  = "medium"
  ram   = "16384"
  vcpus = "4"
  disk  = "35"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "medium-highmem" {
  name  = "medium-highmem"
  ram   = "32768"
  vcpus = "4"
  disk  = "67"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "large" {
  name  = "large"
  ram   = "32768"
  vcpus = "8"
  disk  = "67"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "small-50GB-ephemeral-disk" {
  name  = "small-50GB-ephemeral-disk"
  ram   = "8192"
  vcpus = "2"
  disk  = "53"
  is_public = "true"
}

resource "openstack_compute_flavor_v2" "medium-highmem-100GB-ephemeral-disk" {
  name  = "medium-highmem-100GB-ephemeral-disk"
  ram   = "32768"
  vcpus = "4"
  disk  = "103"
  is_public = "true"
}

# floating ips
resource "openstack_networking_floatingip_v2" "cf_haproxy_public_ip" {
  region = "${var.region_name}"
  pool   = "${var.ext_net_name}"

  provisioner "local-exec" {
    command = <<EOF
      echo cf_haproxy_public_ip: ${openstack_networking_floatingip_v2.cf_haproxy_public_ip.address} >> ../terraform-vars.yml
    EOF
  }
}

resource "openstack_networking_floatingip_v2" "rabbitmq_haproxy_public_ip" {
  region = "${var.region_name}"
  pool   = "${var.ext_net_name}"

  provisioner "local-exec" {
    command = <<EOF
      echo rabbitmq_haproxy_public_ip: ${openstack_networking_floatingip_v2.rabbitmq_haproxy_public_ip.address} >> ../terraform-vars.yml
    EOF
  }
}

resource "openstack_networking_floatingip_v2" "prometheus_nginx_public_ip" {
  region = "${var.region_name}"
  pool   = "${var.ext_net_name}"

  provisioner "local-exec" {
    command = <<EOF
      echo prometheus_nginx_public_ip: ${openstack_networking_floatingip_v2.prometheus_nginx_public_ip.address} >> ../terraform-vars.yml
    EOF
  }
}

output "cf_haproxy_external_ip" {
  value = "${openstack_networking_floatingip_v2.cf_haproxy_public_ip.address}"
}

output "rabbitmq_haproxy_external_ip" {
  value = "${openstack_networking_floatingip_v2.rabbitmq_haproxy_public_ip.address}"
}

output "prometheus_nginx_external_ip" {
  value = "${openstack_networking_floatingip_v2.prometheus_nginx_public_ip.address}"
}
