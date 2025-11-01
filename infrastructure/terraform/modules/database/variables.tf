variable "region" {
  description = "Azure region"
  type        = string
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
}

variable "sku_name" {
  description = "PostgreSQL SKU name"
  type        = string
}

variable "db_storage_mb" {
  description = "Database storage size in MB (50TB = 52,428,800 MB for Premium SSD v2)"
  type        = number
  default     = 52428800  # 50TB in MB
}

variable "db_storage_tier" {
  description = "Storage tier for Premium SSD v2 (P1-P80)"
  type        = string
  default     = "P70"
}


variable "admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Backup retention days"
  type        = number
  default     = 7
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

variable "db_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "13"
}

