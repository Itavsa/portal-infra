variable "resource_prefix" {
  type    = string
  default = "itavsa-portal"
}

variable "resource_location" {
  type    = string
  default = "westeurope"
}

variable "resource_tag" {
  type    = string
  default = "itavsa-tf"
}

variable "db_version" {
  type    = string
  default = "14"
}

variable "db_storage_mb" {
  type    = number
  default = 32768
}

variable "db_sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "db_name" {
  type    = string
  default = "portal"
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "ca_back_image" {
  type    = string
  default = "ghcr.io/itavsa/portal-back:0.0.1-snapshot"
}

variable "ca_back_cpu" {
  type    = number
  default = 0.5
}

variable "ca_back_memory" {
  type    = string
  default = "1Gi"
}

variable "ca_back_port" {
  type    = number
  default = 8080
}

variable "ca_back_probe_path" {
  type    = string
  default = "/actuator/health"
}
variable "ca_front_image" {
  type    = string
  default = "ghcr.io/itavsa/portal-front:0.0.1-snapshot"
}

variable "ca_front_cpu" {
  type    = number
  default = 0.25
}

variable "ca_front_memory" {
  type    = string
  default = "0.5Gi"
}

variable "ca_front_port" {
  type    = number
  default = 80
}