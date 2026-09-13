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

variable "oidc_issuer_url" {
  type = string
}

variable "dns_zone_resource_id" {
  type = string
}

variable "harbor_fqdn" {
  type = string
}

variable "user_object_id" {
  type    = string
  default = ""
}

variable "enable_oidc_auth" {
  type    = bool
  default = true
}

variable "harbor_oidc_app_display_name" {
  type    = string
  default = "harbor-oidc-sso"
}

variable "harbor_admin_group_name" {
  type    = string
  default = "harbor-admins"
}

variable "harbor_projectadmin_group_name" {
  type    = string
  default = "harbor-projectadmins"
}

variable "harbor_maintainer_group_name" {
  type    = string
  default = "harbor-maintainers"
}

variable "harbor_developer_group_name" {
  type    = string
  default = "harbor-developers"
}

variable "harbor_guest_group_name" {
  type    = string
  default = "harbor-guests"
}

variable "harbor_limited_guest_group_name" {
  type    = string
  default = "harbor-limited-guests"
}

variable "harbor_admin_group_member_upns" {
  type    = list(string)
  default = []
}

variable "tags" {
  type = map(string)
}
