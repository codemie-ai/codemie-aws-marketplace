output "terraform_states_s3_bucket_name" {
  description = "Amazon S3 bucket name for remote Terraform state storage"
  value       = aws_s3_bucket.terraform_states.id
}

