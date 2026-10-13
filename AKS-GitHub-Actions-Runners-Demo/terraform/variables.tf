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
  description = "Azure region supporting the selected VM size."
  type        = string
  default     = "northeurope"
}

variable "api_server_authorized_ip_ranges" {
  description = "Public IPv4 CIDRs allowed to reach the AKS API, including your workstation's egress IP."
  type        = list(string)

  validation {
    condition = length(var.api_server_authorized_ip_ranges) > 0 && alltrue([
      for cidr in var.api_server_authorized_ip_ranges :
      can(cidrnetmask(cidr)) && !contains(["0.0.0.0/0", "203.0.113.10/32"], cidr)
    ])
    error_message = "Provide real IPv4 CIDRs; do not use unrestricted access or the example placeholder."
  }
}

variable "kubernetes_version" {
  description = "Optional supported Kubernetes 1.29+ version. Null selects AKS's recommended version."
  type        = string
  default     = null

  validation {
    condition = var.kubernetes_version == null ? true : (
      can(regex("^1\\.(29|[3-9][0-9])(\\.[0-9]+)?$", var.kubernetes_version))
    )
    error_message = "Use a supported Kubernetes 1.29+ version or null."
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

variable "node_vm_size" {
  description = "Non-burstable x86-64 VM size for both pools; runner images target amd64."
  type        = string
  default     = "Standard_D4as_v5"
}

variable "runner_node_max_count" {
  description = "Maximum runner nodes. ARC's runner count is configured separately in arc/runner-values.yaml."
  type        = number
  default     = 3

  validation {
    condition     = var.runner_node_max_count >= 1 && var.runner_node_max_count <= 10 && floor(var.runner_node_max_count) == var.runner_node_max_count
    error_message = "Choose an integer between 1 and 10."
  }
}
