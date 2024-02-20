terraform {
  required_providers {
    azurerm       = {
      source      = "hashicorp/azurerm"
      version     = "3.92.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "b0019fad-dab9-44d7-8ce9-d2943a830c18"
  client_id       = "cc9d3cad-37db-484c-9a9f-d568298f4dd6"
  client_secret   = "MPR8Q~7rFu~gtcxtcBZu1ojgaW6uYNSjLgIDxayz"
  tenant_id       = "4468283d-61db-4cfb-8c2d-7d87f3551df2"
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.project-name}-rg"
  location = var.location
}

resource "azurerm_storage_account" "storage" {
  name                     = "${var.project-name}sa"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "container" {
  name                  = "${var.project-name}container"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "blob"
  depends_on = [ azurerm_storage_account.storage ]
}

resource "azurerm_storage_blob" "blob" {
  name                   = "${var.project-name}blob"
  storage_account_name   = azurerm_storage_account.storage.name
  storage_container_name = azurerm_storage_container.container.name
  type                   = "Block"
  source                 = "sample.txt"
  depends_on = [ azurerm_storage_container.container ]
}

