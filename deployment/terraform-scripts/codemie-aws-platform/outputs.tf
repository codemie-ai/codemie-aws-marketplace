output "region" {
  description = "The AWS region where the resources are deployed"
  value       = var.region
}

output "codemie_aws_role_arn" {
  description = "The ARN of the IAM role that have access to the AWS KMS key and AWS Bedrock"
  value       = module.ai_run_irsa.arn
}

output "codemie_kms_key_id" {
  description = "The ID of the AWS KMS key used for encryption user data"
  value       = module.ai_run_kms.key_id
}

output "codemie_kms_key_arn" {
  description = "The ARN of the AWS KMS key used for encryption user data"
  value       = module.ai_run_kms.key_arn
}

output "codemie_s3_bucket_name" {
  description = "The S3 bucket name used for storing user data in CodeMie"
  value       = module.s3_bucket.s3_bucket_id
}

output "codemie_s3_bucket_region" {
  description = "The S3 bucket region"
  value       = module.s3_bucket.s3_bucket_region
}

output "codemie_vpc_private_subnets" {
  description = "The ID's of private subnets"
  value       = module.vpc.private_subnets
}

output "codemie_vpc_default_sg_id" {
  description = "The Default SG's id"
  value       = module.vpc.default_security_group_id
}

output "rds_address" {
  description = ""
  value       = module.db.db_instance_address
}

output "rds_database_name" {
  description = ""
  value       = module.db.db_instance_name
}

output "rds_database_user" {
  description = ""
  value       = module.db.db_instance_username
  sensitive   = true
}

output "rds_database_password" {
  description = ""
  value       = random_password.rds_master_password.result
  sensitive   = true
}

output "codemie_cache_endpoint" {
  value = module.elasticache.replication_group_primary_endpoint_address
}

output "codemie_cache_secret" {
  value     = random_password.cache_master_password.result
  sensitive = true
}

