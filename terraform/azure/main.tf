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
  name     = "${var.resource.prefix}-rg"
  location = var.resource.location
}

# Virtual network
resource "azurerm_virtual_network" "portal" {
  name                = "${var.resource.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.resource.location
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
  address_prefixes     = ["10.0.2.0/23"] # TODO: try that but container_app_environment.infrastructure_subnet_id's spec tells Subnet must have a /21 or larger address space (/23 works while setup from the portal)
}

# Database DNS zone
resource "azurerm_private_dns_zone" "portal_db" {
  name                  = "${var.resource.prefix}-db.private.postgres.database.azure.com"
  resource_group_name   = azurerm_resource_group.portal.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "portal_db" {
  name                  = "${var.resource.prefix}-db-dns-zone-link"
  private_dns_zone_name = azurerm_private_dns_zone.portal_db.name
  virtual_network_id    = azurerm_virtual_network.portal.id
  resource_group_name   = azurerm_resource_group.portal.name
}

# Database
resource "azurerm_postgresql_flexible_server" "portal" {
  name                   = "${var.resource.prefix}-db"
  resource_group_name    = azurerm_resource_group.portal.name
  location               = var.resource.location
  version                = var.db.version
  delegated_subnet_id    = azurerm_subnet.postgresql.id
  private_dns_zone_id    = azurerm_private_dns_zone.portal_db.id
  administrator_login    = var.db.username
  administrator_password = var.db.password

  storage_mb = var.db.storage_mb

  sku_name   = var.db.sku_name
  depends_on = [azurerm_private_dns_zone_virtual_network_link.portal_db]
}

resource "azurerm_postgresql_flexible_server_database" "portal" {
  name      = var.db.name
  server_id = azurerm_postgresql_flexible_server.portal.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Containers
resource "azurerm_log_analytics_workspace" "portal" {
  name                = "${var.resource.prefix}-ca-analytics"
  location            = var.resource.location
  resource_group_name = azurerm_resource_group.portal.name
  sku                 = "Free"
}

resource "azurerm_container_app_environment" "portal" {
  name                           = "${var.resource.prefix}-ca-env"
  resource_group_name            = azurerm_resource_group.portal.name
  location                       = var.resource.location
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.portal.id
  infrastructure_subnet_id       = azurerm_subnet.containers.id
  internal_load_balancer_enabled = true
}

resource "azurerm_container_app" "portal_back" {
  name                         = "${var.resource.prefix}-ca-back"
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
      image  = var.ca_back.image
      cpu    = var.ca_back.cpu
      memory = var.ca_back.memory
      liveness_probe {
        port = var.ca_back.port
        path = var.ca_back.probe_path
        transport = "HTTPS"
      }
      env {
        name  = "SPRING_DATASOURCE_URL"
        value = "jdbc:postgresql://${azurerm_private_dns_zone.portal_db.name}:5432/${azurerm_postgresql_flexible_server_database.portal.name}?sslmode=require"
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
    target_port      = var.ca_back.port
    external_enabled = true
    traffic_weight {
      percentage = 100
    }
    # TODO: check if it allows traffic from anywhere
    # TODO: check if needs for allow_insecure_connections = true
  }
  depends_on = [azurerm_postgresql_flexible_server_database.portal]
}

resource "azurerm_container_app" "portal_front" {
  name                         = "${var.resource.prefix}-ca-front"
  container_app_environment_id = azurerm_container_app_environment.portal.id
  resource_group_name          = azurerm_resource_group.portal.name
  revision_mode                = "Single"
  template {
    container {
      name   = "portal-front"
      image  = var.ca_front.image
      cpu    = var.ca_front.cpu
      memory = var.ca_front.memory
      env {
        name  = "API_URL"
        value = azurerm_container_app.portal_back.ingress[0].fqdn
      }
    }
  }
  ingress {
    target_port      = var.ca_front.port
    external_enabled = true
    traffic_weight {
      percentage = 100
    }
    # TODO: check if it allows traffic from anywhere
    # TODO: check if needs for allow_insecure_connections = true
  }
  depends_on = [azurerm_container_app.portal_back]
}