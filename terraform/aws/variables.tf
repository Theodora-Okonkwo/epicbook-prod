variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "MySQL database name"
  type        = string
  default     = "bookstore"
}

variable "db_username" {
  description = "MySQL master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "MySQL master password"
  type        = string
  sensitive   = true
}
