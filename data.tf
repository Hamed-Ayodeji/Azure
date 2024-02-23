data "azurerm_client_config" "current" {}
data "template_cloudinit_config" "config" {
  gzip           = true
  base64_encode  = true
  part {
    content_type = "text/cloud-config"
    content      = "packages: ['apache2']"
  }
}