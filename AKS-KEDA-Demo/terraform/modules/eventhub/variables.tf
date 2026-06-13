variable "namespace_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "eventhub_name" {
  type    = string
  default = "keda-demo-hub"
}

variable "partition_count" {
  type    = number
  default = 4
}

variable "message_retention" {
  type    = number
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
