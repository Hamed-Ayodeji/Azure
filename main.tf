terraform {
  required_providers {
    azurerm                       = {
      source                      = "hashicorp/azurerm"
      version                     = "3.92.0"
    }
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  client_id                       = var.client_id
  client_secret                   = var.client_secret
  tenant_id                       = var.tenant_id
  features {}
}

resource "azurerm_resource_group" "rg" {
  name                            = "${var.project-name}-rg"
  location                        = var.location
}

resource "azurerm_storage_account" "storage" {
  name                            = "${var.project-name}storage0818"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  depends_on                      = [ azurerm_resource_group.rg ]
}

resource "azurerm_storage_container" "container" {
  name                            = "${var.project-name}container"
  storage_account_name            = azurerm_storage_account.storage.name
  container_access_type           = "blob"
  depends_on                      = [ azurerm_storage_account.storage ]
}

resource "azurerm_storage_blob" "blob" {
  name                            = "${var.project-name}blob"
  storage_account_name            = azurerm_storage_account.storage.name
  storage_container_name          = azurerm_storage_container.container.name
  type                            = "Block"
  source                          = "custom-script-ext.sh"
  depends_on                      = [ azurerm_storage_container.container ]
}

resource "azurerm_virtual_network" "vnet" {
  name                            = "${var.project-name}-vnet"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  address_space                   = [ var.vnet_address_space ]
  depends_on                      = [ azurerm_resource_group.rg ]
}

resource "azurerm_subnet" "subnets" {
  for_each                        = {
    subnet-1                      = 0
    subnet-2                      = 1
  }
  name                            = each.key
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.vnet.name
  address_prefixes                = [ cidrsubnet(var.vnet_address_space, 4, each.value) ]
  depends_on                      = [ azurerm_virtual_network.vnet ]
}

resource "azurerm_network_interface" "nic" {
  name                            = "${var.project-name}-nic"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnets["subnet-1"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
  depends_on                      = [ azurerm_subnet.subnets, azurerm_public_ip.publicip ]
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "${var.project-name}-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = "adminuser"
  network_interface_ids           = [ azurerm_network_interface.nic.id ]
  availability_set_id             = azurerm_availability_set.availability-set.id

  admin_ssh_key {
    username                      = "adminuser"
    public_key                    = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching                       = "ReadWrite"
    storage_account_type          = "Standard_LRS"
  }

  source_image_reference {
    publisher                     = "Canonical"
    offer                         = "UbuntuServer"
    sku                           = "18.04-LTS"
    version                       = "latest"
  }
  depends_on                      = [ azurerm_network_interface.nic, azurerm_availability_set.availability-set ]
}

resource "azurerm_virtual_machine_extension" "vmext" {
  name                            = "${var.project-name}-vmext"
  virtual_machine_id              = azurerm_linux_virtual_machine.vm.id
  publisher                       = "Microsoft.Azure.Extensions"
  type                            = "CustomScript"
  type_handler_version            = "2.0"
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.storage.name}.blob.core.windows.net/${azurerm_storage_container.container.name}/${azurerm_storage_blob.blob.name}"],
        "commandToExecute": "bash custom-script-ext.sh"
    }
  
  SETTINGS
  depends_on                      = [ azurerm_linux_virtual_machine.vm, azurerm_storage_blob.blob ]
}

resource "azurerm_public_ip" "publicip" {
  name                            = "${var.project-name}-publicip"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  allocation_method               = "Dynamic"
}

resource "azurerm_managed_disk" "disk" {
  name                            = "${var.project-name}-disk"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  storage_account_type            = "Standard_LRS"
  create_option                   = "Empty"
  disk_size_gb                    = 10
}

resource "azurerm_virtual_machine_data_disk_attachment" "disk-attachment" {
  managed_disk_id                 = azurerm_managed_disk.disk.id
  virtual_machine_id              = azurerm_linux_virtual_machine.vm.id
  lun                             = 0
  caching                         = "ReadWrite"
  depends_on                      = [ azurerm_managed_disk.disk, azurerm_linux_virtual_machine.vm]
}

resource "azurerm_availability_set" "availability-set" {
  name                            = "${var.project-name}-availability-set"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  platform_fault_domain_count     = 3
  platform_update_domain_count    = 3
}