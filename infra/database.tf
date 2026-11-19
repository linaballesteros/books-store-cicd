variable "db_admin_password" {
  description = "RDS administrator password for provisioning and database bootstrap."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = can(regex("^[!-~]{16,128}$", var.db_admin_password)) && !can(regex("[/@\"]", var.db_admin_password))
    error_message = "Use 16 to 128 printable ASCII characters, without spaces, slashes, at signs, or double quotes."
  }
}

variable "db_admin_password_version" {
  description = "Increase this value when rotating the RDS administrator password."
  type        = number
  default     = 1
}

locals {
  db_port       = 5432
  db_app_user   = "bookstore_app"
  is_production = local.environment == "production"
}

resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-db"
  description = "BookStore PostgreSQL access from Fargate tasks"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}

resource "aws_db_subnet_group" "database" {
  name       = "${local.name_prefix}-db"
  subnet_ids = data.aws_subnets.public.ids
}

resource "aws_db_instance" "database" {
  identifier                 = "${local.name_prefix}-db"
  engine                     = "postgres"
  engine_version             = "17"
  instance_class             = "db.t4g.micro"
  allocated_storage          = 20
  storage_type               = "gp3"
  storage_encrypted          = true
  multi_az                   = false
  auto_minor_version_upgrade = true
  db_name                    = "bookstore"
  port                       = local.db_port
  username                   = "bookstore_admin"
  password_wo                = var.db_admin_password
  password_wo_version        = var.db_admin_password_version
  db_subnet_group_name       = aws_db_subnet_group.database.name
  vpc_security_group_ids     = [aws_security_group.database.id]
  publicly_accessible        = false
  backup_retention_period    = local.is_production ? 7 : 1
  skip_final_snapshot        = !local.is_production
  final_snapshot_identifier  = local.is_production ? "${local.name_prefix}-db-final" : null
}

output "db_host" {
  description = "Hostname used by the database bootstrap and BookStore backend."
  value       = aws_db_instance.database.address
}
