terraform {
  required_providers {
    cloudru = {
      source  = "cloudru/cloud"
      version = "2.1.5"
    }
  }
}

provider "cloudru" {
  project_id  = var.project_id
  auth_key_id = var.auth_key_id
  auth_secret = var.auth_secret

  endpoints = {
    iam_endpoint     = "iam.api.cloud.ru:443"
    compute_endpoint = "compute.api.cloud.ru:443"
    vpc_endpoint     = "vpc.api.cloud.ru:443"
    nlb_endpoint     = "nlb.api.cloud.ru:443"
  }
}

variable "project_id" {
  type = string
}

variable "auth_key_id" {
  type      = string
  sensitive = true
}

variable "auth_secret" {
  type      = string
  sensitive = true
}

variable "ssh_public_key_path" {
  type = string
}

variable "ssh_source_cidr" {
  type        = string
  description = "CIDR source allowed to connect to SSH. Hosted GitHub Actions require a public source range."
  default     = "0.0.0.0/0"
}

variable "flavor" {
  type        = string
  description = "Cloud.ru Evolution VM flavor name for 2 vCPU and 4 GB RAM."
}

variable "k3s_enabled" {
  type        = bool
  description = "Create the optional two-node K3s cluster and public load balancer."
  default     = false
}

variable "k3s_token" {
  type        = string
  description = "Private token used by K3s nodes to join the cluster."
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.k3s_enabled || length(var.k3s_token) >= 32
    error_message = "Set a K3s token with at least 32 characters when k3s_enabled is true."
  }
}

variable "zone" {
  type    = string
  default = "ru.AZ-1"
}

locals {
  vm_name      = "diploma-vm"
  k3s_roles    = ["server", "worker"]
  k3s_node_ips = ["10.20.0.20", "10.20.0.21"]

  cloud_config = templatefile("${path.module}/cloud-init.yaml.tpl", {
    ssh_public_key = trimspace(file(var.ssh_public_key_path))
    vm_name        = local.vm_name
  })
}

data "cloudru_evolution_compute_image_collection" "ubuntu" {
  project_id = var.project_id
  page_size  = 100
}

resource "cloudru_evolution_vpc_vpc" "diploma" {
  name        = "diploma-vpc"
  project_id  = var.project_id
  description = "Network for the diploma DevOps project"
}

resource "cloudru_evolution_compute_subnet" "diploma" {
  project_id = var.project_id
  name       = "diploma-subnet"

  zone = {
    name = var.zone
  }

  description    = "Subnet for the diploma VM"
  subnet_address = "10.20.0.0/24"
  routed_network = true
  default        = false
  vpc_id         = cloudru_evolution_vpc_vpc.diploma.id

  dns_servers = {
    value = ["8.8.4.4", "8.8.8.8"]
  }
}

resource "cloudru_evolution_compute_security_group" "diploma" {
  project_id = var.project_id
  name       = "diploma-security-group"

  zone = {
    name = var.zone
  }

  description = "Access rules for the diploma VM"
}

resource "cloudru_evolution_compute_security_group_rule" "ssh" {
  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "22:22"
  description       = "SSH for administration and GitHub Actions deployment"
  remote_ip_prefix  = var.ssh_source_cidr
}

resource "cloudru_evolution_compute_security_group_rule" "http" {
  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "80:80"
  description       = "Public HTTP access to the application"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "cloudru_evolution_compute_security_group_rule" "egress_tcp" {
  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_EGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "1:65535"
  description       = "Outbound TCP for operating system and container updates"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "cloudru_evolution_compute_security_group_rule" "egress_udp" {
  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_EGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_UDP"
  port_range        = "1:65535"
  description       = "Outbound UDP for DNS and network services"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "cloudru_evolution_compute_security_group_rule" "k3s_api" {
  count = var.k3s_enabled ? 1 : 0

  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "6443:6443"
  description       = "K3s API access inside the private subnet"
  remote_ip_prefix  = "10.20.0.0/24"
}

resource "cloudru_evolution_compute_security_group_rule" "k3s_nodeport" {
  count = var.k3s_enabled ? 1 : 0

  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "30080:30080"
  description       = "NGINX NodePort access inside the private subnet"
  remote_ip_prefix  = "10.20.0.0/24"
}

resource "cloudru_evolution_compute_security_group_rule" "k3s_kubelet" {
  count = var.k3s_enabled ? 1 : 0

  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "10250:10250"
  description       = "Kubelet communication inside the private subnet"
  remote_ip_prefix  = "10.20.0.0/24"
}

resource "cloudru_evolution_compute_security_group_rule" "k3s_flannel" {
  count = var.k3s_enabled ? 1 : 0

  security_group_id = cloudru_evolution_compute_security_group.diploma.id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_UDP"
  port_range        = "8472:8472"
  description       = "Flannel VXLAN communication inside the private subnet"
  remote_ip_prefix  = "10.20.0.0/24"
}

resource "cloudru_evolution_compute_disk" "diploma" {
  project_id = var.project_id
  name       = "diploma-boot-disk"
  size       = 30

  zone = {
    name = var.zone
  }

  disk_type = {
    name = "SSD"
  }

  description = "Boot disk for the diploma VM"
  bootable    = true
  image = {
    id = [for image in data.cloudru_evolution_compute_image_collection.ubuntu.images : image.id if image.name == "ubuntu-22.04"][0]
  }
  encrypted = false
  readonly  = false
  shared    = false
}

resource "cloudru_evolution_compute_external_ip" "diploma" {
  project_id = var.project_id
  name       = "diploma-public-ip"
  zone = {
    name = var.zone
  }
  description = "Public address for the diploma service"
}

resource "cloudru_evolution_compute_interface" "diploma" {
  project_id = var.project_id
  name       = "diploma-interface"

  zone = {
    name = var.zone
  }

  description                = "Network interface for the diploma VM"
  subnet                     = { id = cloudru_evolution_compute_subnet.diploma.id }
  interface_security_enabled = true

  security_groups = [{ id = cloudru_evolution_compute_security_group.diploma.id }]

  attach_external_ip = { id = cloudru_evolution_compute_external_ip.diploma.id }

  type = "INTERFACE_TYPE_REGULAR"
}

resource "cloudru_evolution_compute_vm" "diploma" {
  project_id = var.project_id
  name       = local.vm_name

  zone = {
    name = var.zone
  }

  flavor = { name = var.flavor }

  description = "Go service diploma demo with CI/CD and monitoring"

  disks = [{ id = cloudru_evolution_compute_disk.diploma.id }]

  network_interfaces = [{
    id = cloudru_evolution_compute_interface.diploma.id
  }]

  cloud_init_userdata = base64encode(local.cloud_config)
}

resource "cloudru_evolution_compute_disk" "k3s" {
  count      = var.k3s_enabled ? 2 : 0
  project_id = var.project_id
  name       = "k3s-${local.k3s_roles[count.index]}-disk"
  size       = 30

  zone = {
    name = var.zone
  }

  disk_type = {
    name = "SSD"
  }

  description = "Boot disk for the ${local.k3s_roles[count.index]} node"
  bootable    = true
  image = {
    id = [for image in data.cloudru_evolution_compute_image_collection.ubuntu.images : image.id if image.name == "ubuntu-22.04"][0]
  }
  encrypted = false
  readonly  = false
  shared    = false
}

resource "cloudru_evolution_compute_nat_gateway" "k3s" {
  count      = var.k3s_enabled ? 1 : 0
  project_id = var.project_id
  name       = "k3s-egress"
  vpc_id     = cloudru_evolution_vpc_vpc.diploma.id

  zone = {
    name = var.zone
  }

  description = "Outbound internet access for private K3s nodes"
}

resource "cloudru_evolution_compute_interface" "k3s" {
  count      = var.k3s_enabled ? 2 : 0
  project_id = var.project_id
  name       = "k3s-${local.k3s_roles[count.index]}-interface"

  zone = {
    name = var.zone
  }

  description                = "Private network interface for the ${local.k3s_roles[count.index]} node"
  ip_address                 = local.k3s_node_ips[count.index]
  subnet                     = { id = cloudru_evolution_compute_subnet.diploma.id }
  interface_security_enabled = true
  security_groups            = [{ id = cloudru_evolution_compute_security_group.diploma.id }]
  type                       = "INTERFACE_TYPE_REGULAR"
}

resource "cloudru_evolution_compute_vm" "k3s" {
  count      = var.k3s_enabled ? 2 : 0
  project_id = var.project_id
  name       = "k3s-${local.k3s_roles[count.index]}"

  zone = {
    name = var.zone
  }

  flavor = { name = var.flavor }

  description = "K3s ${local.k3s_roles[count.index]} node"
  disks       = [{ id = cloudru_evolution_compute_disk.k3s[count.index].id }]
  network_interfaces = [{
    id = cloudru_evolution_compute_interface.k3s[count.index].id
  }]

  cloud_init_userdata = base64encode(templatefile("${path.module}/k3s-cloud-init.yaml.tpl", {
    node_role      = local.k3s_roles[count.index]
    node_ip        = local.k3s_node_ips[count.index]
    server_ip      = local.k3s_node_ips[0]
    k3s_token      = var.k3s_token
    ssh_public_key = trimspace(file(var.ssh_public_key_path))
  }))

  depends_on = [cloudru_evolution_compute_nat_gateway.k3s]
}

resource "cloudru_evolution_nlb_target_group" "k3s" {
  count      = var.k3s_enabled ? 1 : 0
  name       = "k3s-targets"
  project_id = var.project_id

  target_vms = [for index in range(2) : {
    id           = cloudru_evolution_compute_vm.k3s[index].id
    interface_id = cloudru_evolution_compute_interface.k3s[index].id
  }]
}

resource "cloudru_evolution_nlb_network_load_balancer" "k3s" {
  count      = var.k3s_enabled ? 1 : 0
  name       = "k3s-balancer"
  project_id = var.project_id
  vpc_id     = cloudru_evolution_vpc_vpc.diploma.id

  external_address = {
    allocate = true
  }

  availability_zones = [{
    name    = var.zone
    subnets = [{ id = cloudru_evolution_compute_subnet.diploma.id }]
  }]

  rules = [{
    name            = "http-to-nginx"
    target_group_id = cloudru_evolution_nlb_target_group.k3s[0].id
    listeners = [{
      name        = "http-80"
      port        = 80
      target_port = 30080
    }]
    health_check = {
      disabled            = false
      port                = 30080
      timeout             = "5s"
      interval            = "30s"
      unhealthy_threshold = 3
      healthy_threshold   = 3
      http = {
        path = "/nginx-health"
      }
    }
    algorithm = "ALG_ROUND_ROBIN"
  }]

  description = "Public HTTP entry point for the Kubernetes service"
}

output "vm_name" {
  value = cloudru_evolution_compute_vm.diploma.name
}

output "vm_internal_ip" {
  value = cloudru_evolution_compute_interface.diploma.ip_address
}

output "external_ip" {
  value = cloudru_evolution_compute_external_ip.diploma.ip_address
}

output "k3s_server_ip" {
  value = var.k3s_enabled ? local.k3s_node_ips[0] : null
}

output "k3s_worker_ip" {
  value = var.k3s_enabled ? local.k3s_node_ips[1] : null
}

output "k3s_load_balancer_ip" {
  value = var.k3s_enabled ? cloudru_evolution_nlb_network_load_balancer.k3s[0].external_address.ipv4 : null
}
