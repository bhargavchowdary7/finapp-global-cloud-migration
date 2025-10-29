terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatessa12345678"
    container_name       = "terraformstatefile"
    key                  = "financial-app.tfstate"
  }
}