variable "region" {
  description = "Azure region"
  type        = string
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
}

variable "account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "ZRS"   #Transaction logs need ZRS for regional data sovereignty.
}

variable "subnet_id" {
  description = "Subnet ID for private endpoint"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "cool_tier_days" {
  description = "Days before moving to Cool tier"
  type        = number
  default     = 90
}

variable "archive_tier_days" {
  description = "Days before moving to Archive tier"
  type        = number
  default     = 365
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "finapp"
}
