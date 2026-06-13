variable "storage_account_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "queue_name" {
  type    = string
  default = "keda-demo-queue"
}

variable "tags" {
  type    = map(string)
  default = {}
}
