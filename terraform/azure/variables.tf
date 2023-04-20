variable "resource" {
  default = {
    prefix   = "itavsa-portal"
    location = "westeurope"
    tag      = "itavsa-tf"
  }
}

variable "db" {
  default = {
    version    = "14"
    storage_mb = 32768
    sku_name   = "B_Standard_B1ms"
    name       = "portal"
    username = "replace_this_username"
    password = "replace_this_password"
  }
}

variable "ca_back" {
  default = {
    image      = "ghcr.io/itavsa/portal-back:0.0.1-snapshot"
    cpu        = 0.5
    memory     = "1Gi"
    port       = 8080
    probe_path = "/actuator/health"
  }
}

variable "ca_front" {
  default = {
    image  = "ghcr.io/itavsa/portal-front:0.0.1-snapshot"
    cpu    = 0.25
    memory = "0.5Gi"
    port   = 80
  }
}