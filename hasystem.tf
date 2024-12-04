terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.11.0"
    }
  }
}

# Variables untuk Autentikasi Azure, Akan di passed melalui Environment Variables (tfvars)
variable "arm_subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "arm_client_id" {
  description = "Azure Service Principal App ID"
  type        = string
}

variable "arm_client_secret" {
  description = "Azure Service Principal Password"
  type        = string
}

variable "arm_tenant_id" {
  description = "Azure Tenant ID"
  type        = string
}

# Resource Provider untuk Region SEA 
provider "azurerm" {
  alias = "sea_provider"
  features {}
  subscription_id = var.arm_subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.arm_tenant_id
}

# Random String untuk Penamaan Unique
resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group untuk region Southeast Asia
resource "azurerm_resource_group" "sea_resource_group" {
  provider = azurerm.sea_provider
  name     = "ha-mainwebapp-rg"
  location = "Southeast Asia"
}

# Network Security Group untuk Web Servers region SEA (VM) 
resource "azurerm_network_security_group" "webapp_nsg" {
  provider            = azurerm.sea_provider
  name                = "webapp-nsg"
  location            = azurerm_resource_group.sea_resource_group.location
  resource_group_name = azurerm_resource_group.sea_resource_group.name

# Definisi Security Rule Inbound/Outbound untuk Web Servers (VM)
  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
  name                       = "allow-outbound-internet"
  priority                   = 120
  direction                  = "Outbound"
  access                     = "Allow"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "*"
  destination_address_prefix = "Internet"
 }

}

# Virtual Network untuk region Southeast Asia
resource "azurerm_virtual_network" "sea_vnet" {
  provider            = azurerm.sea_provider
  name                = "sea-webapp-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.sea_resource_group.location
  resource_group_name = azurerm_resource_group.sea_resource_group.name
}

# Subnet untuk region Southeast Asia
resource "azurerm_subnet" "sea_subnet" {
  provider             = azurerm.sea_provider
  name                 = "sea-webapp-subnet"
  resource_group_name  = azurerm_resource_group.sea_resource_group.name
  virtual_network_name = azurerm_virtual_network.sea_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP untuk Load Balancer pada region Southeast Asia
resource "azurerm_public_ip" "sea_lb_public_ip" {
  provider            = azurerm.sea_provider
  name                = "sea-lb-publicip"
  location            = azurerm_resource_group.sea_resource_group.location
  resource_group_name = azurerm_resource_group.sea_resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Load Balancer untuk region Southeast Asia
resource "azurerm_lb" "sea_load_balancer" {
  provider            = azurerm.sea_provider
  name                = "sea-webapp-lb"
  location            = azurerm_resource_group.sea_resource_group.location
  resource_group_name = azurerm_resource_group.sea_resource_group.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "sea-lb-frontend"
    public_ip_address_id = azurerm_public_ip.sea_lb_public_ip.id
  }
}

# Load Balancer Backend Address Pool
resource "azurerm_lb_backend_address_pool" "sea_backend_pool" {
  provider        = azurerm.sea_provider
  loadbalancer_id = azurerm_lb.sea_load_balancer.id
  name            = "sea-backend-pool"
}

# Health Probe untuk Load Balancer Southeast Asia
resource "azurerm_lb_probe" "sea_health_probe" {
  provider            = azurerm.sea_provider
  loadbalancer_id     = azurerm_lb.sea_load_balancer.id
  name                = "sea-health-probe"
  port                = 80
  protocol            = "Http"
  request_path        = "/"
  interval_in_seconds = 15
  number_of_probes    = 3
}

# Load Balancing Rule untuk Load Balancer Southeast Asia
resource "azurerm_lb_rule" "sea_lb_rule" {
  provider                       = azurerm.sea_provider
  loadbalancer_id                = azurerm_lb.sea_load_balancer.id
  name                           = "sea-lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "sea-lb-frontend"
  probe_id                       = azurerm_lb_probe.sea_health_probe.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.sea_backend_pool.id]
}

# Asosiasi VM's dengan Backend Pool Load balancer pada Southeast Asia
resource "azurerm_network_interface_backend_address_pool_association" "sea_backend_pool_assoc" {
  count                   = 3
  provider                = azurerm.sea_provider
  network_interface_id    = azurerm_network_interface.sea_nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.sea_backend_pool.id
}

# Storage Account untuk region Southeast Asia
resource "azurerm_storage_account" "sea_storage" {
  provider                 = azurerm.sea_provider
  name                     = "seawebappstorage${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.sea_resource_group.name
  location                 = azurerm_resource_group.sea_resource_group.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"
}

# Konfigurasi Virtual Machines pada Availability Zones berbeda (Southeast Asia)
resource "azurerm_linux_virtual_machine" "sea_webservers" {
  count               = 3
  provider            = azurerm.sea_provider
  name                = "sea-webserver-${count.index + 1}"
  resource_group_name = azurerm_resource_group.sea_resource_group.name
  location            = azurerm_resource_group.sea_resource_group.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  
  zone = tostring(count.index + 1)  # Distribusi VMs sepanjang Availabity Zones 1, 2, 3

  network_interface_ids = [
    azurerm_network_interface.sea_nic[count.index].id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("C:/Users/rocke/.ssh/id_rsa.pub")  # Key SSH Admin untuk Konfigurasi Awal
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  } 


 # Konfigurasi Template File untuk menjalankan VM Setup Script Saat Infrastruktur dideploy
  custom_data = base64encode(templatefile("${path.module}/vm-setup-script.sh", {
    STORAGE_ACCOUNT_NAME = azurerm_storage_account.sea_storage.name
    STORAGE_ACCOUNT_KEY  = azurerm_storage_account.sea_storage.primary_access_key
    REGION               = "SEA"
    SERVER_NUMBER        = count.index + 1
  }))

} 

# Network Interfaces untuk Web Servers (VM) Southeast Asia 
resource "azurerm_network_interface" "sea_nic" {
  count               = 3
  provider            = azurerm.sea_provider
  name                = "sea-webserver-nic-${count.index + 1}"
  location            = azurerm_resource_group.sea_resource_group.location
  resource_group_name = azurerm_resource_group.sea_resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sea_subnet.id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }

  ip_configuration {
    name                          = "secondary"
    subnet_id                     = azurerm_subnet.sea_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Apply (Associate) NSG kepada Network Interfaces
resource "azurerm_network_interface_security_group_association" "sea_nsg_association" {
  count                     = 3
  provider                  = azurerm.sea_provider
  network_interface_id      = azurerm_network_interface.sea_nic[count.index].id
  network_security_group_id = azurerm_network_security_group.webapp_nsg.id
}

# Recovery Services Vault untuk Backup SEA VM
resource "azurerm_recovery_services_vault" "backup_vault_sea" {
  provider            = azurerm.sea_provider
  name                = "sea-webapp-backup-vault"
  location            = azurerm_resource_group.sea_resource_group.location
  resource_group_name = azurerm_resource_group.sea_resource_group.name
  sku                 = "Standard"
}

# Backup Policy untuk Backup SEA VM
resource "azurerm_backup_policy_vm" "comprehensive_backup_policy" {
  provider            = azurerm.sea_provider
  name                = "comprehensive-backup-policy"
  resource_group_name = azurerm_resource_group.sea_resource_group.name
  recovery_vault_name = azurerm_recovery_services_vault.backup_vault_sea.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 7
  }

  retention_weekly {
    count    = 4
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 3
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
}

# Konfigurasi Backup SEA VM
resource "azurerm_backup_protected_vm" "sea_vm_backups" {
  count               = 3
  provider            = azurerm.sea_provider
  resource_group_name = azurerm_resource_group.sea_resource_group.name
  recovery_vault_name = azurerm_recovery_services_vault.backup_vault_sea.name
  source_vm_id        = azurerm_linux_virtual_machine.sea_webservers[count.index].id
  backup_policy_id    = azurerm_backup_policy_vm.comprehensive_backup_policy.id
}

# Output Public Load Balancer IP
output "webapp_load_balancer_ip" {
  value = azurerm_public_ip.sea_lb_public_ip.ip_address
}