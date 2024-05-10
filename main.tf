#===============================================================================
#                                   RANDOMS
#===============================================================================
resource "random_string" "name" {
  length  = 8
  lower   = true
  numeric = false
  special = false
  upper   = false
}

resource "random_password" "password" {
  length           = 10
  lower            = true
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  numeric          = true
  special          = true
  upper            = true
  override_special = "_"
}

#===============================================================================
#                                   RESOURCE GROUP
#===============================================================================
resource "azurerm_resource_group" "rg" {
  name     = "3-tier-app-rg"
  location = var.resource_group_location
}

#===============================================================================
#                              NETWORKING CONFIGURATION
#===============================================================================
#                                    NETWORKS
#===============================================================================
resource "azurerm_virtual_network" "aks-vnet" {
  name                = "aks-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "aks-sn" {
  name                 = "aks-sn"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.aks-vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_virtual_network" "db-vnet" {
  name                = "db-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["172.16.0.0/16"]
}

resource "azurerm_subnet" "db-sn" {
  name                 = "db-sn"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.db-vnet.name
  address_prefixes     = ["172.16.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "fs"

    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

#===============================================================================
#                               NETWORKS PEEERING
#===============================================================================
resource "azurerm_virtual_network_peering" "aks-to-db" {
  name                         = "aks-to-db-peering"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_network_name         = azurerm_virtual_network.aks-vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.db-vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "db-to-aks" {
  name                         = "db-to-aks-peering"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_network_name         = azurerm_virtual_network.db-vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.aks-vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

#===============================================================================
#                               DNS CONFIGURATION
#===============================================================================
resource "azurerm_private_dns_zone" "db-dns" {
  name                = "fs.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "db-registration-link" {
  name                  = "db-registration-link"
  resource_group_name   = azurerm_resource_group.rg.name
  virtual_network_id    = azurerm_virtual_network.db-vnet.id
  private_dns_zone_name = azurerm_private_dns_zone.db-dns.name
  registration_enabled  = true

  depends_on = [azurerm_private_dns_zone.db-dns]
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks-resolution-link" {
  name                  = "aks-resolution-link"
  resource_group_name   = azurerm_resource_group.rg.name
  virtual_network_id    = azurerm_virtual_network.aks-vnet.id
  private_dns_zone_name = azurerm_private_dns_zone.db-dns.name
  registration_enabled  = false

  depends_on = [azurerm_private_dns_zone_virtual_network_link.db-registration-link]
}

#===============================================================================
#                               AKS CLUSTER
#===============================================================================
#                               SSH KEY GEN
#===============================================================================
resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = "ssh-key"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id
}

resource "azapi_resource_action" "ssh_public_key_gen" {
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]
}

output "key_data" {
  value = jsondecode(azapi_resource_action.ssh_public_key_gen.output).publicKey
}
#===============================================================================
#                                  CLUSTER
#===============================================================================
resource "azurerm_kubernetes_cluster" "k8s" {
  location            = azurerm_resource_group.rg.location
  name                = "aks-cluster"
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks"

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name           = "agentpool"
    vm_size        = "Standard_DS2_v2"
    node_count     = var.node_count
    vnet_subnet_id = azurerm_subnet.aks-sn.id
  }

  linux_profile {
    admin_username = var.username
    ssh_key {
      key_data = jsondecode(azapi_resource_action.ssh_public_key_gen.output).publicKey
    }
  }

  network_profile {
    network_plugin = "azure"
  }
}
#===============================================================================
#                            MYSQL FLEXIBLE SERVER
#===============================================================================
resource "azurerm_mysql_flexible_server" "default" {
  name                         = format("mysqlfs-%s", random_string.name.result)
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  administrator_login          = random_string.name.result
  administrator_password       = random_password.password.result
  backup_retention_days        = 7
  delegated_subnet_id          = azurerm_subnet.db-sn.id
  geo_redundant_backup_enabled = false
  private_dns_zone_id          = azurerm_private_dns_zone.db-dns.id
  sku_name                     = "GP_Standard_D2ds_v4"
  version                      = "8.0.21"

  high_availability {
    mode = "SameZone"
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 8
    start_minute = 0
  }

  storage {
    iops    = 360
    size_gb = 20
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.db-registration-link]
}

resource "azurerm_mysql_flexible_server_configuration" "require_secure_transport" {
  name                = "require_secure_transport"
  value               = "OFF"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.default.name
}
#===============================================================================
#                           MYSQL FLEXIBLE DATABASE
#===============================================================================
resource "azurerm_mysql_flexible_database" "main" {
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
  name                = "mytho"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.default.name

  depends_on = [azurerm_mysql_flexible_server.default]
}
#===============================================================================
