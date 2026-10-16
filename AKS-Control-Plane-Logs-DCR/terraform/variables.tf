variable "project" {
  description = "Short lowercase project name used in dedicated demo resource names."
  type        = string
  default     = "dcrlogs"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project))
    error_message = "Use 3-20 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "location" {
  description = "Azure region supporting AKS and Log Analytics."
  type        = string
  default     = "eastus2"
}

variable "node_vm_size" {
  description = "AKS system node size; choose a SKU available within your regional quota."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "api_server_authorized_ip_ranges" {
  description = "Optional public client CIDRs permitted to reach the Kubernetes API. Empty disables IP restrictions; Kubernetes authentication is still required."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.api_server_authorized_ip_ranges :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Use an empty list to disable IP restrictions, or IPv4 CIDRs with prefix /24 or narrower, preferably your public IP/32."
  }
}
