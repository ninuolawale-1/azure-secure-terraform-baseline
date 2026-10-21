terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Subscription ID comes from a variable (or the ARM_SUBSCRIPTION_ID env var)
# instead of being hardcoded in source control.
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "core"
}

provider "azuread" {}

# Resource group
resource "azurerm_resource_group" "mtc-reg" {
  name     = "rg-development"
  location = var.location
  tags = {
    env = "dev"
  }
}

resource "azurerm_virtual_network" "mtc_vn" {
  name                = "mtc-network"
  resource_group_name = azurerm_resource_group.mtc-reg.name
  location            = azurerm_resource_group.mtc-reg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    env = "dev"
  }
}

resource "azurerm_subnet" "mtc-subnet" {
  name                 = "mtc-subnet"
  resource_group_name  = azurerm_resource_group.mtc-reg.name
  virtual_network_name = azurerm_virtual_network.mtc_vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "mtc-security" {
  name                = "mtc-sg"
  location            = azurerm_resource_group.mtc-reg.location
  resource_group_name = azurerm_resource_group.mtc-reg.name

  tags = {
    environment = "dev"
  }
}

# Inbound SSH only, only from the operator's IP (was: all ports from any source)
resource "azurerm_network_security_rule" "mtc-dev-rule" {
  name                       = "allow-ssh-from-admin-ip"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = var.allowed_source_ip
  destination_address_prefix = "*"

  resource_group_name         = azurerm_resource_group.mtc-reg.name
  network_security_group_name = azurerm_network_security_group.mtc-security.name
}

resource "azurerm_subnet_network_security_group_association" "mtc-sga" {
  subnet_id                 = azurerm_subnet.mtc-subnet.id
  network_security_group_id = azurerm_network_security_group.mtc-security.id
}

resource "azurerm_public_ip" "mtc-public" {
  name                = "mtc-public-ip"
  resource_group_name = azurerm_resource_group.mtc-reg.name
  location            = azurerm_resource_group.mtc-reg.location
  allocation_method   = "Static"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "mtc-nic" {
  name                = "mtc-nic"
  location            = azurerm_resource_group.mtc-reg.location
  resource_group_name = azurerm_resource_group.mtc-reg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mtc-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mtc-public.id
  }

  tags = {
    environment = "dev"
  }
}

# SSH key auth only; no admin password stored in code or state
resource "azurerm_linux_virtual_machine" "mtc-vm" {
  name                            = "mtc-virtual-machine"
  resource_group_name             = azurerm_resource_group.mtc-reg.name
  location                        = azurerm_resource_group.mtc-reg.location
  size                            = "Standard_D2s_v3"
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.mtc-nic.id,
  ]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Adds the new VM to the local SSH config so it's reachable by name right after apply
  provisioner "local-exec" {
    command = templatefile("mac-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = var.admin_username,
      identityfile = var.ssh_private_key_path
    })
    interpreter = ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }
}

data "azurerm_public_ip" "mtc-ip-data" {
  name                = azurerm_public_ip.mtc-public.name
  resource_group_name = azurerm_resource_group.mtc-reg.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.mtc-vm.name}: ${data.azurerm_public_ip.mtc-ip-data.ip_address}"
}
