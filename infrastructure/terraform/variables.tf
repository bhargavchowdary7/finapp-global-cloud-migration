variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "Production"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "FinApp"
}

variable "cost_center" {
  description = "Cost center code"
  type        = string
  default     = "9876"
}

# Regions as per PDF requirements
variable "regions" {
  description = "Azure regions for deployment matching PDF requirements"
  type = map(object({
    region           = string
    db_sku_name      = string
    db_storage_mb    = number
    db_version       = string
    storage_account_tier = string
    storage_replication_type = string
  }))
}

variable "existing_vnet_name" {
  description = "Name of existing VNet"
  type        = string
}

variable "existing_subnet_name" {
  description = "Name of existing subnet for private endpoints"
  type        = string
}

variable "admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 7
}

variable "lifecycle_cool_tier_days" {
  description = "Days before moving blobs to Cool tier"
  type        = number
  default     = 90
}

variable "lifecycle_archive_tier_days" {
  description = "Days before moving blobs to Archive tier"
  type        = number
  default     = 365
}

variable "regions" {
  description = "Azure regions for sovereign deployment"
  type = map(string)
  default = {
    "na" = "East US 2"        # North America
    "eu" = "UK South"         # Europe (UK)
    "asia" = "Southeast Asia" # Asia (Singapore)
  }
}

variable "sql_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "SQL Server administrator password - will be retrieved from Key Vault"
  type        = string
  sensitive   = true
  default     = null  # No default, must come from Key Vault
}