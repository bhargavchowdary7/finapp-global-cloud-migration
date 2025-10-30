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

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
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

variable "enable_geo_backup" {
  description = "Enable geo-redundant backups for disaster recovery"
  type        = bool
  default     = true  # Enable by default for production
}