terraform {

  required_version = "= 1.13.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.56.0"
    }
  }

}

provider "aws" {
  region = var.region

  assume_role {
    role_arn = var.role_arn
  }
}
