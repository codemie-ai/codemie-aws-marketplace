################################################################################
# AI/Run IAM Role for Service Account
################################################################################
module "ai_run_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name                 = "AWSIRSA_${replace(upper(local.cluster_name), "-", "")}_AI_RUN"
  use_name_prefix      = false
  trust_condition_test = "StringLike"
  permissions_boundary = var.role_permissions_boundary_arn

  policies = {
    AIRunKMSPolicy     = aws_iam_policy.ai_run_kms_policy.arn
    AIRunBedrockPolicy = aws_iam_policy.ai_run_bedrock_policy.arn
    AIRunS3Policy      = aws_iam_policy.ai_run_s3_policy.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["*"]
    }
  }

  tags = local.tags
}

################################################################################
# IAM Role for Cluster Addons Service Accounts
################################################################################
module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name                 = "AWSIRSA_${replace(title(local.cluster_name), "-", "")}_VPC_CNI"
  permissions_boundary = var.role_permissions_boundary_arn
  use_name_prefix      = false

  policies = {
    AmazonEKS_CNI_Policy = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
  tags = local.tags
}

module "aws_ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name                 = "AWSIRSA_${replace(title(local.cluster_name), "-", "")}_EBS_CSI_Driver"
  use_name_prefix      = false
  permissions_boundary = var.role_permissions_boundary_arn

  policies = {
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}
