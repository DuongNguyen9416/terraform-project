resource "azurerm_resource_group" "function_app_rg" {
  name     = var.resource_group_name
  location = "westeurope" # Ensure the region is allowed
  tags     = {
    Environment = "Development"
    Owner       = "DuongNguyen"
  }
}

# Storage Account for the Function App
resource "azurerm_storage_account" "function_app_storage" {
  name                     = "funcappstorage${random_string.suffix.result}" # Must be globally unique
  resource_group_name      = azurerm_resource_group.function_app_rg.name
  location                 = azurerm_resource_group.function_app_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Random string to ensure unique storage account name
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Virtual Network for the Function App
resource "azurerm_virtual_network" "function_app_vnet" {
  name                = "func-app-vnet"
  location            = azurerm_resource_group.function_app_rg.location
  resource_group_name = azurerm_resource_group.function_app_rg.name
  address_space       = ["10.0.0.0/16"]
}

# Subnet for the Function App
resource "azurerm_subnet" "function_app_subnet" {
  name                 = "func-app-subnet"
  resource_group_name  = azurerm_resource_group.function_app_rg.name
  virtual_network_name = azurerm_virtual_network.function_app_vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "delegation-to-app-service"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoint_subnet" {
  name                 = "private-endpoint-subnet"
  resource_group_name  = azurerm_resource_group.function_app_rg.name
  virtual_network_name = azurerm_virtual_network.function_app_vnet.name
  address_prefixes     = ["10.0.2.0/24"] # Ensure this does not overlap with other subnets
}

# App Service Plan for the Function App
resource "azurerm_service_plan" "function_app_plan" {
  name                = "func-app-plan"
  location            = azurerm_resource_group.function_app_rg.location
  resource_group_name = azurerm_resource_group.function_app_rg.name
  os_type             = "Linux"
  sku_name            = "B1" # Correct SKU

  tags = {
    Environment = "Development"
    Owner       = "DuongNguyen"
  }
}

# Function App
resource "azurerm_linux_function_app" "function_app" {
  name                       = "func-app-${random_string.suffix.result}"
  location                   = azurerm_resource_group.function_app_rg.location
  resource_group_name        = azurerm_resource_group.function_app_rg.name
  service_plan_id            = azurerm_service_plan.function_app_plan.id
  storage_account_name       = azurerm_storage_account.function_app_storage.name
  storage_account_access_key = azurerm_storage_account.function_app_storage.primary_access_key

  public_network_access_enabled = false
  https_only                    = true

  site_config {
    ftps_state          = "FtpsOnly"
    minimum_tls_version = "1.2"
  }

  app_settings = {
    "AzureWebJobsStorage"         = azurerm_storage_account.function_app_storage.primary_connection_string
    "FUNCTIONS_EXTENSION_VERSION" = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
  }

  virtual_network_subnet_id = azurerm_subnet.function_app_subnet.id
}

resource "azurerm_private_endpoint" "function_app_private_endpoint" {
  name                = "func-app-private-endpoint"
  location            = azurerm_resource_group.function_app_rg.location
  resource_group_name = azurerm_resource_group.function_app_rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "func-app-connection"
    private_connection_resource_id = azurerm_linux_function_app.function_app.id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }
}

# Private DNS Zone for the Function App
resource "azurerm_private_dns_zone" "function_app_dns_zone" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.function_app_rg.name
}

# Link the DNS Zone to the Virtual Network
resource "azurerm_private_dns_zone_virtual_network_link" "function_app_dns_link" {
  name                  = "func-app-dns-link"
  resource_group_name   = azurerm_resource_group.function_app_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.function_app_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.function_app_vnet.id
}

# Add DNS Records for the Private Endpoint
resource "azurerm_private_dns_a_record" "function_app_dns_record" {
  name                = azurerm_linux_function_app.function_app.name
  zone_name           = azurerm_private_dns_zone.function_app_dns_zone.name
  resource_group_name = azurerm_resource_group.function_app_rg.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.function_app_private_endpoint.private_service_connection[0].private_ip_address]
}

# Add Service Bus Namespace
resource "azurerm_servicebus_namespace" "service_bus_namespace" {
  name                = "func-app-sb-${random_string.suffix.result}"
  location            = azurerm_resource_group.function_app_rg.location
  resource_group_name = azurerm_resource_group.function_app_rg.name
  sku = "Standard"
  
  tags = {
    Environment = "Development"
    Owner       = "DuongNguyen"
  }
}

#Add Service Bus Queue
resource "azurerm_servicebus_queue" "service_bus_queue" {
  name                       = "func-app-queue"
  namespace_id               = azurerm_servicebus_namespace.service_bus_namespace.id
  max_size_in_megabytes      = 1024
  requires_duplicate_detection = true
  lock_duration              = "PT5M"
  dead_lettering_on_message_expiration = true
}

# Add Service Bus Topic
resource "azurerm_servicebus_topic" "service_bus_topic" {
  name                = "func-app-topic"
  namespace_id        = azurerm_servicebus_namespace.service_bus_namespace.id
  max_size_in_megabytes = 1024
}

# Add Service Bus Subscription
resource "azurerm_servicebus_subscription" "service_bus_subscription" {
  name                = "func-app-subscription"
  topic_id            = azurerm_servicebus_topic.service_bus_topic.id
  max_delivery_count  = 10
  lock_duration       = "PT5M"
}
