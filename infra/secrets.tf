variable "db_app_password" {
  description = "PostgreSQL password shared by the bootstrap task and Express."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(trimspace(var.db_app_password)) >= 16
    error_message = "The application database password must contain at least 16 characters."
  }
}

variable "db_ingest_password" {
  description = "PostgreSQL password for the read-only ingest role created by bootstrap."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(trimspace(var.db_ingest_password)) >= 16
    error_message = "The ingest database password must contain at least 16 characters."
  }
}

variable "db_runtime_password_version" {
  description = "Increase this value when rotating the application or ingest database password."
  type        = number
  default     = 1
}

resource "aws_ssm_parameter" "db_admin_password" {
  name             = "/bookstore/${local.environment}/db/admin-password"
  type             = "SecureString"
  value_wo         = var.db_admin_password
  value_wo_version = var.db_admin_password_version
}

resource "aws_ssm_parameter" "db_app_password" {
  name             = "/bookstore/${local.environment}/db/app-password"
  type             = "SecureString"
  value_wo         = var.db_app_password
  value_wo_version = var.db_runtime_password_version
}

resource "aws_ssm_parameter" "db_ingest_password" {
  name             = "/bookstore/${local.environment}/db/ingest-password"
  type             = "SecureString"
  value_wo         = var.db_ingest_password
  value_wo_version = var.db_runtime_password_version
}
