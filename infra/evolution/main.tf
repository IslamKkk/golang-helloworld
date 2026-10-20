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

variable "zone" {
  type    = string
  default = "ru.AZ-1"
}

locals {
  vm_name = "diploma-vm"

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

  zone_identifier = {
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

  zone_identifier = {
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

resource "cloudru_evolution_compute_disk" "diploma" {
  project_id = var.project_id
  name       = "diploma-boot-disk"
  size       = 30

  zone_identifier = {
    name = var.zone
  }

  disk_type_identifier = {
    name = "SSD"
  }

  description = "Boot disk for the diploma VM"
  bootable    = true
  image_id    = [for image in data.cloudru_evolution_compute_image_collection.ubuntu.images : image.id if image.name == "ubuntu-22.04"][0]
  encrypted   = false
  readonly    = false
  shared      = false
}

resource "cloudru_evolution_compute_interface" "diploma" {
  project_id = var.project_id
  name       = "diploma-interface"

  zone_identifier = {
    name = var.zone
  }

  description                = "Network interface for the diploma VM"
  subnet_id                  = cloudru_evolution_compute_subnet.diploma.id
  interface_security_enabled = true

  security_groups_identifiers = {
    value = [{
      id = cloudru_evolution_compute_security_group.diploma.id
    }]
  }

  external_ip_specs = {
    new_external_ip = true
  }

  type = "INTERFACE_TYPE_REGULAR"
}

resource "cloudru_evolution_compute_vm" "diploma" {
  project_id = var.project_id
  name       = local.vm_name

  zone_identifier = {
    name = var.zone
  }

  flavor_identifier = {
    name = var.flavor
  }

  description = "Go service diploma demo with CI/CD and monitoring"

  disk_identifiers = [{
    disk_id = cloudru_evolution_compute_disk.diploma.id
  }]

  network_interfaces = [{
    interface_id = cloudru_evolution_compute_interface.diploma.id
  }]

  cloud_init_userdata = base64encode(local.cloud_config)
}

output "vm_name" {
  value = cloudru_evolution_compute_vm.diploma.name
}

output "vm_internal_ip" {
  value = cloudru_evolution_compute_interface.diploma.ip_address
}

output "external_ip" {
  value = cloudru_evolution_compute_interface.diploma.external_ip.ip_address
}
