variable "subscription_id" {
  description = "Azure subscription ID. Set in terraform.tfvars (gitignored) or via ARM_SUBSCRIPTION_ID."
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "admin_username" {
  description = "Admin username for the Linux VM"
  type        = string
  default     = "adminuser"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key used for VM login"
  type        = string
  default     = "~/.ssh/azurekey.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the matching SSH private key (used only locally to write the SSH config; never uploaded)"
  type        = string
  default     = "~/.ssh/azurekey"
}

variable "allowed_source_ip" {
  description = "Your public IP in CIDR form (e.g. x.x.x.x/32). Only this address can reach SSH."
  type        = string
}
