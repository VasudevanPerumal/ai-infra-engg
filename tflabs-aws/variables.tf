variable "participant_name" {
  description = "Participant name used in resource naming"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability Zone used for all subnets in this lab"
  type        = string
  default     = "us-east-1a"
}

variable "admin_password" {
  description = "Shared local administrator password configured on the lab instances"
  type        = string
  sensitive   = true
}

variable "app_instance_type" {
  description = "EC2 instance type for the Linux app server"
  type        = string
  default     = "t3.small"
}

variable "db_instance_type" {
  description = "EC2 instance type for the Linux database server"
  type        = string
  default     = "t3.small"
}

variable "win_instance_type" {
  description = "EC2 instance type for the Windows server"
  type        = string
  default     = "t3.small"
}