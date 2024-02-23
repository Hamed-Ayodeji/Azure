terraform {
  required_providers {
    azurerm                       = {
      source                      = "hashicorp/azurerm"
      version                     = "3.92.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# resource "random_id" "unique" {
#   byte_length                     = 8
# } .hex

# resource "random_pet" "unique" {
#   length                          = 2
#   separator                       = "-"
# } .id

resource "random_string" "unique" {
  length                          = 5
  special                         = false
  upper                           = false
  numeric                         = true
  lower                           = true
} # .result

resource "tls_private_key" "rsakey" {
  algorithm                       = "RSA"
  rsa_bits                        = 4096
}

resource "local_file" "linux-key" {
  content                         = tls_private_key.rsakey.private_key_pem
  filename                        = "${var.project-name}key.pem"
}

resource "azurerm_resource_group" "rg" {
  name                            = "${var.project-name}-rg"
  location                        = var.location
}

resource "azurerm_storage_account" "storage" {
  name                            = "${var.project-name}str${random_string.unique.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  depends_on                      = [ azurerm_resource_group.rg, random_string.unique]
}

resource "azurerm_storage_container" "container" {
  name                            = "${var.project-name}container"
  storage_account_name            = azurerm_storage_account.storage.name
  container_access_type           = "blob"
  depends_on                      = [ azurerm_storage_account.storage ]
}

resource "azurerm_storage_blob" "blob" {
  name                            = "${var.project-name}blob.sh"
  storage_account_name            = azurerm_storage_account.storage.name
  storage_container_name          = azurerm_storage_container.container.name
  type                            = "Block"
  source                          = "${var.project-name}blob.sh"
  depends_on                      = [ azurerm_storage_container.container ]
}

resource "azurerm_storage_blob" "windows-blob" {
  name                            = "${var.project-name}blob.ps1"
  storage_account_name            = azurerm_storage_account.storage.name
  storage_container_name          = azurerm_storage_container.container.name
  type                            = "Block"
  source                          = "${var.project-name}blob.ps1"
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
  count                           = var.countNumber
  name                            = count.index == 0 ? "linux-subnet" : count.index == 1 ? "win-subnet" : format("extra-subnet-%d", count.index - 1)
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.vnet.name
  address_prefixes                = [ cidrsubnet(var.vnet_address_space, 4, count.index) ]
  depends_on                      = [ azurerm_virtual_network.vnet ]
}

resource "azurerm_network_interface" "nic" {
  count                           = length(azurerm_subnet.subnets)
  name                            = "${var.project-name}-nic-${count.index}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnets[count.index].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip[count.index].id
  }
  depends_on                      = [ azurerm_subnet.subnets, azurerm_public_ip.publicip ]
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "${var.project-name}-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = "adminuser"
  custom_data                     = data.template_cloudinit_config.config.rendered
  network_interface_ids           = [ azurerm_network_interface.nic[0].id ]
  availability_set_id             = azurerm_availability_set.availability-set.id

  admin_ssh_key {
    username                      = "adminuser"
    public_key                    = tls_private_key.rsakey.public_key_openssh
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

resource "azurerm_windows_virtual_machine" "windows-vm" {
  name                            = "${var.project-name}-winvm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = "adminuser"
  admin_password                  = azurerm_key_vault_secret.keyvault-secret.value
  network_interface_ids           = [ azurerm_network_interface.nic[1].id ]
  availability_set_id             = azurerm_availability_set.availability-set.id

  os_disk {
    caching                       = "ReadWrite"
    storage_account_type          = "Standard_LRS"
  }

  source_image_reference {
    publisher                     = "MicrosoftWindowsServer"
    offer                         = "WindowsServer"
    sku                           = "2019-Datacenter"
    version                       = "latest"
  }
  depends_on                      = [ azurerm_network_interface.nic, azurerm_availability_set.availability-set, azurerm_key_vault_secret.keyvault-secret ]
  
}

# resource "azurerm_virtual_machine_extension" "linux-vmext" {
#   name                            = "${var.project-name}-linux-vmext"
#   virtual_machine_id              = azurerm_linux_virtual_machine.vm.id
#   publisher                       = "Microsoft.Azure.Extensions"
#   type                            = "CustomScript"
#   type_handler_version            = "2.0"
#   settings = <<SETTINGS
#     {
#         "fileUris": ["https://${azurerm_storage_account.storage.name}.blob.core.windows.net/${azurerm_storage_container.container.name}/${azurerm_storage_blob.blob.name}"],
#         "commandToExecute": "bash ${azurerm_storage_blob.blob.name}"
#     }
#   SETTINGS
#   depends_on                      = [ azurerm_linux_virtual_machine.vm, azurerm_storage_blob.blob ]
# }

resource "azurerm_virtual_machine_extension" "windows-vmext" {
  name                            = "${var.project-name}-windows-vmext"
  virtual_machine_id              = azurerm_windows_virtual_machine.windows-vm.id
  publisher                       = "Microsoft.Compute"
  type                            = "CustomScriptExtension"
  type_handler_version            = "1.10"
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.storage.name}.blob.core.windows.net/${azurerm_storage_container.container.name}/${azurerm_storage_blob.windows-blob.name}"],
        "commandToExecute": "powershell -ExecutionPolicy Unrestricted -File ${azurerm_storage_blob.windows-blob.name}"
    }
  SETTINGS
  depends_on                      = [ azurerm_windows_virtual_machine.windows-vm, azurerm_storage_blob.windows-blob ]
  
}

resource "azurerm_public_ip" "publicip" {
  count                           = length(azurerm_subnet.subnets)
  name                            = "${var.project-name}-publicip-${count.index}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  allocation_method               = "Dynamic"
}

resource "azurerm_managed_disk" "linux_disk" {
  name                            = "${var.project-name}-linux_disk"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  storage_account_type            = "Standard_LRS"
  create_option                   = "Empty"
  disk_size_gb                    = 10
}

resource "azurerm_managed_disk" "win_disk" {
  name                            = "${var.project-name}-win_disk"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  storage_account_type            = "Standard_LRS"
  create_option                   = "Empty"
  disk_size_gb                    = 10
}

resource "azurerm_virtual_machine_data_disk_attachment" "disk-attachment" {
  managed_disk_id                 = azurerm_managed_disk.linux_disk.id
  virtual_machine_id              = azurerm_linux_virtual_machine.vm.id
  lun                             = 0
  caching                         = "ReadWrite"
  depends_on                      = [ azurerm_managed_disk.linux_disk, azurerm_linux_virtual_machine.vm]
}

resource "azurerm_virtual_machine_data_disk_attachment" "windows-disk-attachment" {
  managed_disk_id                 = azurerm_managed_disk.win_disk.id
  virtual_machine_id              = azurerm_windows_virtual_machine.windows-vm.id
  lun                             = 0
  caching                         = "ReadWrite"
  depends_on                      = [ azurerm_managed_disk.win_disk, azurerm_windows_virtual_machine.windows-vm ]
}

resource "azurerm_availability_set" "availability-set" {
  name                            = "${var.project-name}-availability-set"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  platform_fault_domain_count     = 3
  platform_update_domain_count    = 3
}

resource "azurerm_network_security_group" "nsg" {
  count                           = length(azurerm_subnet.subnets)
  name                            = count.index == 0 ? "linux-nsg" : count.index == 1 ? "win-nsg" : format("extra-nsg-%d", count.index - 1)
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "ssh-rule" {
  name                            = "${var.project-name}-ssh-rule"
  priority                        = 100
  direction                       = "Inbound"
  access                          = "Allow"
  protocol                        = "Tcp"
  source_port_range               = "*"
  destination_port_range          = "22"
  source_address_prefix           = "*"
  destination_address_prefix      = "*"
  resource_group_name             = azurerm_resource_group.rg.name
  network_security_group_name     = azurerm_network_security_group.nsg[0].name
}

resource "azurerm_network_security_rule" "http-rule" {
  count                           = length(azurerm_network_security_group.nsg)
  name                            = "${var.project-name}-http-rule"
  priority                        = 101
  direction                       = "Inbound"
  access                          = "Allow"
  protocol                        = "Tcp"
  source_port_range               = "*"
  destination_port_range          = "80"
  source_address_prefix           = "*"
  destination_address_prefix      = "*"
  resource_group_name             = azurerm_resource_group.rg.name
  network_security_group_name     = azurerm_network_security_group.nsg[count.index].name
}

resource "azurerm_network_security_rule" "https-rule" {
  count                           = length(azurerm_network_security_group.nsg)
  name                            = "${var.project-name}-https-rule"
  priority                        = 102
  direction                       = "Inbound"
  access                          = "Allow"
  protocol                        = "Tcp"
  source_port_range               = "*"
  destination_port_range          = "443"
  source_address_prefix           = "*"
  destination_address_prefix      = "*"
  resource_group_name             = azurerm_resource_group.rg.name
  network_security_group_name     = azurerm_network_security_group.nsg[count.index].name
}

resource "azurerm_network_security_rule" "icmp-rule" {
  count                           = length(azurerm_network_security_group.nsg)
  name                            = "${var.project-name}-icmp-rule"
  priority                        = 103
  direction                       = "Inbound"
  access                          = "Allow"
  protocol                        = "Icmp"
  source_port_range               = "*"
  destination_port_range          = "*"
  source_address_prefix           = "*"
  destination_address_prefix      = "*"
  resource_group_name             = azurerm_resource_group.rg.name
  network_security_group_name     = azurerm_network_security_group.nsg[count.index].name
}

resource "azurerm_network_interface_security_group_association" "nsg-association" {
  count                           = length(azurerm_network_security_group.nsg)
  network_interface_id            = count.index == 0 ? azurerm_network_interface.nic[0].id : azurerm_network_interface.nic[1].id
  network_security_group_id       = azurerm_network_security_group.nsg[count.index].id
  depends_on                      = [ azurerm_network_security_group.nsg, azurerm_network_interface.nic ]
}

resource "azurerm_key_vault" "keyvault" {
  name                            = "${var.project-name}-kv-${random_string.unique.result}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false
  depends_on                      = [ azurerm_resource_group.rg, random_string.unique ]
}

resource "azurerm_key_vault_access_policy" "keyvault-policy" {
  key_vault_id                    = azurerm_key_vault.keyvault.id
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  object_id                       = data.azurerm_client_config.current.object_id
  secret_permissions              = [ "Get", "Backup", "Delete", "List", "Purge", "Recover", "Restore", "Set" ]
  key_permissions                 = [ "Get", "List", "Delete", "Create", "Import", "Recover", "Backup", "Restore" ]
  storage_permissions             = [ "Get", "List" ]
  depends_on                      = [ azurerm_key_vault.keyvault ]
}

resource "azurerm_key_vault_secret" "keyvault-secret" {
  name                            = "secret"
  value                           = var.win_password
  key_vault_id                    = azurerm_key_vault.keyvault.id
  depends_on                      = [ azurerm_key_vault.keyvault, azurerm_key_vault_access_policy.keyvault-policy]
}