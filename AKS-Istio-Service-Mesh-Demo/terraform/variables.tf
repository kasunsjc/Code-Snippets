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
    Leave empty to auto-detect AKS's current default supported revision for
    `location`/`kubernetes_version` via `az aks mesh get-revisions` (requires
    az CLI login + the aks-preview extension; see scripts/default-istio-revision.sh).
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

# --- cert-manager + Azure DNS (TLS for the Istio ingress gateway) -------------

variable "dns_zone_name" {
  description = "Name of an EXISTING Azure DNS zone (e.g. example.com) already delegated to Azure DNS. This demo does not create the zone."
  type        = string
}

variable "dns_zone_resource_group" {
  description = "Resource group that contains the existing Azure DNS zone."
  type        = string
}

variable "bookinfo_subdomain" {
  description = "Subdomain the bookinfo sample app is exposed on, combined with dns_zone_name (e.g. bookinfo-demo -> bookinfo-demo.example.com)."
  type        = string
  default     = "bookinfo"
}

variable "acme_email" {
  description = "Contact email registered with Let's Encrypt for certificate expiry notices."
  type        = string
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
