variable "resource_group_name" {
  type        = string
  description = "Resource group name for the capstone stack."
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "eastus"
}

variable "prefix" {
  type        = string
  description = "Name prefix for resource naming."
  default     = "finbridge"
}

variable "vm_size" {
  type        = string
  description = "VM size for the jumpbox VM."
  default     = "Standard_B2s"
}

variable "admin_username" {
  type        = string
  description = "Admin username for Linux VM."
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key value for Linux VM access."
}

variable "my_public_ip_cidr" {
  type        = string
  description = "Operator public IP in CIDR format allowed for SSH (example: 203.0.113.10/32)."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all supported resources."
  default = {
    environment = "capstone"
    owner       = "ops"
    workload    = "finbridge"
    tower       = "storage"
  }
}
