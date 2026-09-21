variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "istio-mesh"
}

variable "environment" {
  description = "Environment short name (e.g. dev, demo, prod)."
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region. Check `az aks mesh get-revisions --location <region>` for Istio add-on availability."
  type        = string
  default     = "northeurope"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Must be >= 1.23 for the Istio add-on; use a recent GA minor version."
  type        = string
  default     = "1.34"
}

variable "node_count" {
  description = "Default (system) node pool node count."
  type        = number
  default     = 3
}

variable "node_vm_size" {
  description = "VM size for the default node pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

# --- Istio service mesh add-on -------------------------------------------------

variable "istio_revisions" {
  description = <<-EOT
    Istio control plane revision(s) to install (e.g. ["asm-1-24"]).
    Leave empty to let AKS install its current default supported revision -
    the actual revision is only known after apply (see the istio_revisions output).
    Set 2 revisions only while performing a canary minor-version upgrade.
  EOT
  type        = list(string)
  default     = []
}

variable "internal_ingress_gateway_enabled" {
  description = "Enable the AKS-managed internal Istio ingress gateway (ClusterIP/internal LB)."
  type        = bool
  default     = false
}

variable "external_ingress_gateway_enabled" {
  description = "Enable the AKS-managed external Istio ingress gateway (public Azure Load Balancer)."
  type        = bool
  default     = true
}

# --- Observability --------------------------------------------------------------

variable "enable_monitoring" {
  description = "Provision Log Analytics + Azure Monitor managed Prometheus + Azure Managed Grafana, the officially verified observability path for the Istio add-on."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
