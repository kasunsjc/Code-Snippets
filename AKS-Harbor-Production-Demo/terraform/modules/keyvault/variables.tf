variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "privatelink_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "kv_csi_identity_object_id" {
  type = string
}

variable "user_object_id" {
  type    = string
  default = ""
}

variable "harbor_admin_password" {
  type = string
}

variable "postgres_password" {
  type = string
}

variable "redis_password" {
  type = string
}

variable "harbor_secret_key" {
  type = string
}

variable "harbor_core_secret" {
  type = string
}

variable "harbor_core_xsrf_key" {
  type = string
}

variable "harbor_jobservice_secret" {
  type = string
}

variable "harbor_registry_http_secret" {
  type = string
}

variable "harbor_registry_passwd" {
  type = string
}

variable "harbor_registry_htpasswd" {
  type = string
}

variable "tags" {
  type = map(string)
}
