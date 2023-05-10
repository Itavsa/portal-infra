terraform {
  required_version = "1.4.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.52.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "portal" {
  name     = "${var.resource_prefix}-rg"
  location = var.resource_location
}

# Virtual network
resource "azurerm_virtual_network" "portal" {
  name                = "${var.resource_prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.resource_location
  resource_group_name = azurerm_resource_group.portal.name
}

resource "azurerm_subnet" "postgresql" {
  name                 = "postgresql"
  virtual_network_name = azurerm_virtual_network.portal.name
  resource_group_name  = azurerm_resource_group.portal.name
  address_prefixes     = ["10.0.0.0/28"]
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "containers" {
  name                 = "containers"
  virtual_network_name = azurerm_virtual_network.portal.name
  resource_group_name  = azurerm_resource_group.portal.name
  address_prefixes     = ["10.0.2.0/23"]
}

# Database DNS zone
resource "azurerm_private_dns_zone" "portal_db" {
  name                = "${var.resource_prefix}-db.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.portal.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "portal_db" {
  name                  = "${var.resource_prefix}-db-dns-zone-link"
  private_dns_zone_name = azurerm_private_dns_zone.portal_db.name
  virtual_network_id    = azurerm_virtual_network.portal.id
  resource_group_name   = azurerm_resource_group.portal.name
}

# Database
resource "azurerm_postgresql_flexible_server" "portal" {
  name                   = "${var.resource_prefix}-db"
  resource_group_name    = azurerm_resource_group.portal.name
  location               = var.resource_location
  version                = var.db_version
  delegated_subnet_id    = azurerm_subnet.postgresql.id
  private_dns_zone_id    = azurerm_private_dns_zone.portal_db.id
  administrator_login    = var.db_username
  administrator_password = var.db_password

  storage_mb = var.db_storage_mb

  sku_name   = var.db_sku_name
  depends_on = [azurerm_private_dns_zone_virtual_network_link.portal_db]
  lifecycle {
    ignore_changes = [
      zone
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "portal" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.portal.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Containers
resource "azurerm_log_analytics_workspace" "portal" {
  name                = "${var.resource_prefix}-ca-analytics"
  location            = var.resource_location
  resource_group_name = azurerm_resource_group.portal.name
  sku                 = "PerGB2018"
}

resource "azurerm_container_app_environment" "portal" {
  name                           = "${var.resource_prefix}-ca-env"
  resource_group_name            = azurerm_resource_group.portal.name
  location                       = var.resource_location
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.portal.id
  infrastructure_subnet_id       = azurerm_subnet.containers.id
  internal_load_balancer_enabled = false
}

resource "azurerm_container_app" "portal_back" {
  name                         = "${var.resource_prefix}-ca-back"
  container_app_environment_id = azurerm_container_app_environment.portal.id
  resource_group_name          = azurerm_resource_group.portal.name
  revision_mode                = "Single"
  secret {
    name  = "spring-datasource-password"
    value = azurerm_postgresql_flexible_server.portal.administrator_password
  }
  template {
    container {
      name   = "portal-back"
      image  = var.ca_back_image
      cpu    = var.ca_back_cpu
      memory = var.ca_back_memory
      liveness_probe {
        port      = var.ca_back_port
        path      = var.ca_back_probe_path
        transport = "HTTPS"
      }
      env {
        name  = "SPRING_DATASOURCE_URL"
        value = "jdbc:postgresql://${azurerm_postgresql_flexible_server.portal.fqdn}:5432/${azurerm_postgresql_flexible_server_database.portal.name}?sslmode=require"
      }
      env {
        name  = "SPRING_DATASOURCE_USERNAME"
        value = azurerm_postgresql_flexible_server.portal.administrator_login
      }
      env {
        name        = "SPRING_DATASOURCE_PASSWORD"
        secret_name = "spring-datasource-password"
      }
    }
  }
  ingress {
    target_port      = var.ca_back_port
    external_enabled = true
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  depends_on = [azurerm_postgresql_flexible_server_database.portal]
}

resource "azurerm_container_app" "portal_front" {
  name                         = "${var.resource_prefix}-ca-front"
  container_app_environment_id = azurerm_container_app_environment.portal.id
  resource_group_name          = azurerm_resource_group.portal.name
  revision_mode                = "Single"
  template {
    container {
      name   = "portal-front"
      image  = var.ca_front_image
      cpu    = var.ca_front_cpu
      memory = var.ca_front_memory
      env {
        name  = "API_URL"
        value = "https://${azurerm_container_app.portal_back.ingress[0].fqdn}"
      }
    }
  }
  ingress {
    target_port      = var.ca_front_port
    external_enabled = true
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  depends_on = [azurerm_container_app.portal_back]
}