
################################################################################
# RDS Postgres
################################################################################
resource "aws_security_group" "rds_security_group" {
  name        = "${var.platform_name}-rds-sg"
  description = "Security group for RDS PostgreSQL - allows traffic only from VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.platform_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.platform_name}-rds-sg"
  })
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "${var.platform_name}-db-subnet-group"
  description = "Subnet group for RDS instance"
  subnet_ids  = module.vpc.private_subnets

  tags = local.tags
}

resource "random_password" "rds_master_password" {
  length           = 16
  special          = true
  override_special = "!#%*()-_"
}

module "db" {
  source     = "terraform-aws-modules/rds/aws"
  version    = "6.13.1"
  identifier = "${var.platform_name}-rds"

  engine                   = "postgres"
  engine_version           = "17.9"
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  family                   = "postgres17"
  storage_type             = "gp3"
  major_engine_version     = "17.9"
  instance_class           = var.pg_instance_class
  maintenance_window       = "sun:02:00-sun:03:00"
  backup_window            = "00:00-01:00"
  backup_retention_period  = 0

  allocated_storage     = 20
  max_allocated_storage = 30

  db_name  = "codemie"
  username = "dbadmin"
  password = random_password.rds_master_password.result
  port     = 5432

  manage_master_user_password = false

  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]

  publicly_accessible = false
  deletion_protection = true

  tags = local.tags
}