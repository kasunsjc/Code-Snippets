variable "project" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "gha-runners"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.project))
    error_message = "Use 3-24 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment identifier."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.environment))
    error_message = "Use 2-8 lowercase letters or digits, starting with a letter."
  }
}

variable "location" {
  description = "Azure region that supports AKS Automatic (requires availability zones)."
  type        = string
  default     = "swedencentral"
}

variable "api_server_authorized_ip_ranges" {
  description = "Optional public IPv4 CIDRs allowed to reach the AKS API. Empty (default) leaves the API publicly reachable, still protected by Entra ID and Azure RBAC. Restricting it is recommended."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.api_server_authorized_ip_ranges :
      can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"
    ])
    error_message = "Provide valid IPv4 CIDRs, or leave the list empty to skip restriction. 0.0.0.0/0 is redundant; use an empty list instead."
  }
}

variable "cache_share_quota_gib" {
  description = "Persistent Premium SMB NuGet cache capacity, billed even when runners scale to zero."
  type        = number
  default     = 100

  validation {
    condition     = var.cache_share_quota_gib >= 100 && var.cache_share_quota_gib <= 1024 && floor(var.cache_share_quota_gib) == var.cache_share_quota_gib
    error_message = "Choose an integer from 100 to 1024 GiB (Premium shares require at least 100 GiB)."
  }
}
