variable "project" {
  description = "Short project name used in Azure resource names."
  type        = string
  default     = "flux"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project))
    error_message = "Use 2-20 lowercase letters, numbers or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name used in Azure resource names."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "Use 2-10 lowercase letters or numbers, starting with a letter."
  }
}

variable "location" {
  description = "Azure region supporting AKS and the Flux extension."
  type        = string
  default     = "northeurope"
}

variable "kubernetes_version" {
  description = "Supported AKS version; null uses the region's default."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "System node VM size; verify regional availability and quota."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "node_count" {
  description = "Number of nodes for this non-production demo."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a positive integer."
  }
}

variable "git_repository_url" {
  description = "Public HTTPS Git repository containing the published demo manifests."
  type        = string

  validation {
    condition     = can(regex("^https://[^/@]+/[^@]+$", var.git_repository_url))
    error_message = "Provide an HTTPS repository URL without embedded credentials."
  }
}

variable "git_branch" {
  description = "Published branch containing the GitOps paths."
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Repository-relative directory containing the external application's Kubernetes manifests or Kustomize configuration."
  type        = string
}