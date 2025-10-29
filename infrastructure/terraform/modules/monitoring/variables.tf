variable "region" {
  description = "Azure region"
  type        = string
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
}

variable "postgresql_id" {
  description = "PostgreSQL server ID"
  type        = string
}

variable "storage_id" {
  description = "Storage account ID"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}