# Backend configuration for storing Terraform state in Azure Storage
# This file should be configured based on your environment

# Uncomment and configure the backend block below for remote state storage
/*
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestorage123"
    container_name       = "tfstate"
    key                  = "storage-migration.terraform.tfstate"
    use_azuread_auth     = true
    subscription_id      = "00000000-0000-0000-0000-000000000000"
  }
}
*/

# Alternative: Local backend (for development)
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Data source to access remote state (if using remote backend)
/*
data "terraform_remote_state" "network" {
  backend = "azurerm"
  
  config = {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestorage123"
    container_name       = "tfstate"
    key                  = "network.terraform.tfstate"
    use_azuread_auth     = true
    subscription_id      = "00000000-0000-0000-0000-000000000000"
  }
}
*/

# If you have an existing storage account for Terraform state, you can use it
# Otherwise, you can create one using the following configuration:

# Resource Group for Terraform State
resource "azurerm_resource_group" "tfstate" {
  count    = var.create_resource_group ? 1 : 0
  name     = "rg-tfstate-${var.environment}"
  location = var.location
  tags = {
    Purpose    = "Terraform State"
    Environment = var.environment
    ManagedBy  = "Terraform"
  }
}

# Storage Account for Terraform State
resource "azurerm_storage_account" "tfstate" {
  count                    = var.create_resource_group ? 1 : 0
  name                     = "sttfstate${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate[0].name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    Purpose    = "Terraform State"
    Environment = var.environment
    ManagedBy  = "Terraform"
  }
}

# Container for Terraform State
resource "azurerm_storage_container" "tfstate" {
  count                 = var.create_resource_group ? 1 : 0
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate[0].id
  container_access_type = "private"
}

# Output state storage information
output "tfstate_storage_account_name" {
  description = "The name of the storage account for Terraform state"
  value       = var.create_resource_group ? azurerm_storage_account.tfstate[0].name : "Use existing storage account"
}

output "tfstate_container_name" {
  description = "The name of the container for Terraform state"
  value       = var.create_resource_group ? azurerm_storage_container.tfstate[0].name : "Use existing container"
}

output "tfstate_resource_group_name" {
  description = "The name of the resource group for Terraform state"
  value       = var.create_resource_group ? azurerm_resource_group.tfstate[0].name : "Use existing resource group"
}