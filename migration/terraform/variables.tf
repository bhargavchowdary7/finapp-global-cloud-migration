# Azure Provider Variables
variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Azure Service Principal App ID"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "Azure Service Principal Password"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure Tenant ID"
  type        = string
  sensitive   = true
}

# Project Configuration
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "storagemigration"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

# Resource Group
variable "create_resource_group" {
  description = "Whether to create a new resource group"
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group (created if not exists)"
  type        = string
  default     = ""
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/19"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

variable "file_share_quota_gb" {
  description = "Quota for Azure File Share in GB"
  type        = number
  default     = 5120
}

variable "create_storage_sync" {
  description = "Whether to create Azure File Sync resources"
  type        = bool
  default     = false
}

# Database Configuration (for database migration)
variable "create_sql_server" {
  description = "Whether to create SQL Server for database migration"
  type        = bool
  default     = false
}

variable "sql_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.sql_admin_password) >= 8
    error_message = "SQL admin password must be at least 8 characters long."
  }
}

# Key Vault Configuration
variable "create_key_vault" {
  description = "Whether to create Azure Key Vault"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "SKU for Key Vault (standard or premium)"
  type        = string
  default     = "standard"
}

# Monitoring
variable "enable_monitoring" {
  description = "Whether to enable Azure Monitor and Log Analytics"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "StorageMigration"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Data Box Configuration (if used)
variable "enable_data_box" {
  description = "Whether to configure Data Box resources"
  type        = bool
  default     = false
}

# Backup Configuration
variable "enable_backup" {
  description = "Whether to enable Azure Backup"
  type        = bool
  default     = false
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Whether to enable private endpoints for storage"
  type        = bool
  default     = false
}

# Cost Management
variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 1000
}