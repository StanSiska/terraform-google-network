/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  subnets = {
    for x in var.subnets :
    "${x.subnet_region}/${x.subnet_name}" => x
  }
}

/******************************************
	VPC configuration
 *****************************************/
resource "google_compute_network" "network" {
  name                    = var.network_name
  auto_create_subnetworks = var.auto_create_subnetworks
  routing_mode            = var.routing_mode
  project                 = var.project_id
  description             = var.description
}

/******************************************
	Shared VPC
 *****************************************/
resource "google_compute_shared_vpc_host_project" "shared_vpc_host" {
  count      = var.shared_vpc_host == "true" ? 1 : 0
  project    = var.project_id
  depends_on = [google_compute_network.network]
}

/******************************************
	Subnet configuration
 *****************************************/
resource "google_compute_subnetwork" "subnetwork" {
  for_each                 = local.subnets
  name                     = each.value.subnet_name
  ip_cidr_range            = each.value.subnet_ip
  region                   = each.value.subnet_region
  private_ip_google_access = lookup(each.value, "subnet_private_access", "false")
  dynamic "log_config" {
    for_each = lookup(each.value, "subnet_flow_logs", false) ? [{
      aggregation_interval = lookup(each.value, "subnet_flow_logs_interval", null)
      flow_sampling        = lookup(each.value, "subnet_flow_logs_sampling", null)
      metadata             = lookup(each.value, "subnet_flow_logs_metadata", null)
    }] : []
    content {
      aggregation_interval = log_config.value.aggregation_interval
      flow_sampling        = log_config.value.flow_sampling
      metadata             = log_config.value.metadata
    }
  }
  network     = google_compute_network.network.name
  project     = var.project_id
  description = lookup(each.value, "description", null)
  secondary_ip_range = [
    for i in range(
      length(
        contains(
        keys(var.secondary_ranges), each.value.subnet_name) == true
        ? var.secondary_ranges[each.value.subnet_name]
        : []
    )) :
    var.secondary_ranges[each.value.subnet_name][i]
  ]
}

/******************************************
	Routes
 *****************************************/
resource "google_compute_route" "route" {
  count                  = length(var.routes)
  project                = var.project_id
  network                = var.network_name
  name                   = lookup(var.routes[count.index], "name", format("%s-%s-%d", lower(var.network_name), "route", count.index))
  description            = lookup(var.routes[count.index], "description", "")
  tags                   = compact(split(",", lookup(var.routes[count.index], "tags", "")))
  dest_range             = lookup(var.routes[count.index], "destination_range", "")
  next_hop_gateway       = lookup(var.routes[count.index], "next_hop_internet", "false") == "true" ? "default-internet-gateway" : ""
  next_hop_ip            = lookup(var.routes[count.index], "next_hop_ip", "")
  next_hop_instance      = lookup(var.routes[count.index], "next_hop_instance", "")
  next_hop_instance_zone = lookup(var.routes[count.index], "next_hop_instance_zone", "")
  next_hop_vpn_tunnel    = lookup(var.routes[count.index], "next_hop_vpn_tunnel", "")
  priority               = lookup(var.routes[count.index], "priority", "1000")

  depends_on = [
    google_compute_network.network,
    google_compute_subnetwork.subnetwork,
  ]
}

resource "null_resource" "delete_default_internet_gateway_routes" {
  count = var.delete_default_internet_gateway_routes ? 1 : 0

  provisioner "local-exec" {
    command = "${path.module}/scripts/delete-default-gateway-routes.sh ${var.project_id} ${var.network_name}"
  }

  triggers = {
    number_of_routes = length(var.routes)
  }

  depends_on = [
    google_compute_network.network,
    google_compute_subnetwork.subnetwork,
    google_compute_route.route,
  ]
}
