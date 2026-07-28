locals {
  tags = merge(
    var.tags,
    {
      "user:tag" = var.platform_name
    },
  )
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name                  = var.deployer_role_name
  description           = "IAM role to assume to deploy and manage EKS cluster and related resources"
  assume_role_policy    = data.aws_iam_policy_document.assume_role_policy.json
  force_detach_policies = true
  permissions_boundary  = var.iam_permissions_boundary_policy_arn

  tags = merge(local.tags, tomap({ "Name" = var.deployer_role_name }))
}

resource "aws_iam_role_policy" "eks_identity_provider_full_access" {
  role = aws_iam_role.deployer.name
  name = "DeployerPolicyEKS-IDP-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeIdentityProviderConfig",
          "eks:AssociateIdentityProviderConfig",
          "eks:ListIdentityProviderConfigs",
          "eks:DisassociateIdentityProviderConfig"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:eks:*:${data.aws_caller_identity.current.account_id}:cluster/*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_iam" {
  role = aws_iam_role.deployer.name
  name = "DeployerPolicyIAM-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:AttachRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:CreateOpenIDConnectProvider",
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:CreateRole",
          "iam:CreateServiceLinkedRole",
          "iam:DeleteInstanceProfile",
          "iam:DeleteOpenIDConnectProvider",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DeleteServiceLinkedRole",
          "iam:DetachRolePolicy",
          "iam:GetInstanceProfile",
          "iam:GetOpenIDConnectProvider",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:List*",
          "iam:PassRole",
          "iam:PutRolePolicy",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:TagOpenIDConnectProvider",
          "iam:TagPolicy",
          "iam:TagRole",
          "iam:UnTagInstanceProfile",
          "iam:UntagOpenIDConnectProvider",
          "iam:UnTagPolicy",
          "iam:UnTagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateOpenIDConnectProviderThumbprint",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_ec2" {
  role = aws_iam_role.deployer.name
  name = "DeployerPolicyEC2-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:AllocateAddress",
          "ec2:AssignPrivateIpAddresses",
          "ec2:Associate*",
          "ec2:AttachInternetGateway",
          "ec2:AttachNetworkInterface",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateDefaultSubnet",
          "ec2:CreateDhcpOptions",
          "ec2:CreateEgressOnlyInternetGateway",
          "ec2:CreateInternetGateway",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:CreateNatGateway",
          "ec2:CreateNetworkInterface",
          "ec2:CreateRoute",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSubnet",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateVpc",
          "ec2:CreateVpcEndpoint",
          "ec2:DeleteDhcpOptions",
          "ec2:DeleteEgressOnlyInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:DeleteKeyPair",
          "ec2:DeleteLaunchTemplate",
          "ec2:DeleteLaunchTemplateVersions",
          "ec2:DeleteNatGateway",
          "ec2:DeleteNetworkInterface",
          "ec2:DeleteRoute",
          "ec2:DeleteRouteTable",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSubnet",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DeleteVpc",
          "ec2:DeleteVpnGateway",
          "ec2:Describe*",
          "ec2:DetachInternetGateway",
          "ec2:DetachNetworkInterface",
          "ec2:DetachVolume",
          "ec2:Disassociate*",
          "ec2:GetLaunchTemplateData",
          "ec2:ImportKeyPair",
          "ec2:ModifyLaunchTemplate",
          "ec2:ModifySubnetAttribute",
          "ec2:ModifyVpcAttribute",
          "ec2:ModifyVpcEndpoint",
          "ec2:ReleaseAddress",
          "ec2:ReplaceRoute",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
          "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
          "ec2:GetSecurityGroupsForVpc",
          "ec2:ReplaceRouteTableAssociation",
          "ec2:DeleteNetworkInterface",
          "ec2:DetachNetworkInterface",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_eks" {
  role = aws_iam_role.deployer.name

  name = "DeployerPolicyEKS-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "autoscaling:AttachInstances",
          "autoscaling:AttachLoadBalancers",
          "autoscaling:AttachLoadBalancerTargetGroups",
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:CreateLaunchConfiguration",
          "autoscaling:CreateOrUpdateTags",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DeleteLaunchConfiguration",
          "autoscaling:DeleteScheduledAction",
          "autoscaling:DeleteTags",
          "autoscaling:Describe*",
          "autoscaling:DetachInstances",
          "autoscaling:DetachLoadBalancers",
          "autoscaling:DetachLoadBalancerTargetGroups",
          "autoscaling:PutScheduledUpdateGroupAction",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:SetInstanceProtection",
          "autoscaling:SuspendProcesses",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:StartInstanceRefresh",
          "eks:AssociateEncryptionConfig",
          "eks:CreateAddon",
          "eks:CreateCluster",
          "eks:CreateFargateProfile",
          "eks:CreateNodegroup",
          "eks:DeleteAddon",
          "eks:DeleteCluster",
          "eks:DeleteFargateProfile",
          "eks:DeleteNodegroup",
          "eks:DescribeAddon",
          "eks:DescribeAddonVersions",
          "eks:DescribeCluster",
          "eks:DescribeFargateProfile",
          "eks:DescribeNodegroup",
          "eks:DescribeUpdate",
          "eks:ListAddons",
          "eks:ListClusters",
          "eks:ListFargateProfiles",
          "eks:ListNodegroups",
          "eks:ListTagsForResource",
          "eks:TagResource",
          "eks:UntagResource",
          "eks:UpdateAddon",
          "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateNodegroupVersion",
          "eks:CreateAccessEntry",
          "eks:ListAccessEntries",
          "eks:DescribeAccessEntry",
          "eks:DeleteAccessEntry",
          "eks:UpdateAccessEntry",
          "eks:ListAccessPolicies",
          "eks:AssociateAccessPolicy",
          "eks:DisassociateAccessPolicy",
          "eks:ListAssociatedAccessPolicies",
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_logs" {
  role = aws_iam_role.deployer.name
  name = "DeployerPolicyLogs-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:ListTagsForResource",
          "logs:ListTagsLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_kms" {
  role = aws_iam_role.deployer.name

  name = "DeployerPolicyKMS-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:CreateAlias",
          "kms:CreateGrant",
          "kms:CreateKey",
          "kms:DeleteAlias",
          "kms:DescribeKey",
          "kms:EnableKeyRotation",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListAliases",
          "kms:ListResourceTags",
          "kms:PutKeyPolicy",
          "kms:ScheduleKeyDeletion",
          "kms:TagResource"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_rds" {
  role = aws_iam_role.deployer.name

  name = "DeployerPolicyRDS-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds:CreateDBSubnetGroup",
          "rds:CreateDBParameterGroup",
          "rds:AddTagsToResource",
          "rds:DescribeDBSubnetGroups",
          "rds:DescribeDBParameterGroups",
          "rds:ListTagsForResource",
          "rds:DescribeDBParameters",
          "rds:DeleteDBSubnetGroup",
          "rds:CreateDBInstance",
          "rds:DescribeDBInstances",
          "rds:DeleteDBInstance",
          "rds:CreateDBSnapshot",
          "rds:ModifyDBInstance",
          "rds:DeleteDBParameterGroup",
          "rds:ModifyDBSubnetGroup"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_cache" {
  role = aws_iam_role.deployer.name

  name = "DeployerPolicyElasticache-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "elasticache:AddTagsToResource",
          "elasticache:CreateCacheParameterGroup",
          "elasticache:CreateCacheSubnetGroup",
          "elasticache:CreateReplicationGroup",
          "elasticache:DeleteCacheSubnetGroup",
          "elasticache:DeleteCacheParameterGroup",
          "elasticache:DeleteReplicationGroup",
          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeCacheParameters",
          "elasticache:DescribeCacheParameterGroups",
          "elasticache:DescribeCacheSubnetGroups",
          "elasticache:DescribeReplicationGroups",
          "elasticache:ListTagsForResource",
          "elasticache:ModifyCacheParameterGroup",
          "elasticache:ModifyReplicationGroup"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_bedrock" {
  role = aws_iam_role.deployer.name

  name = "DeployerPolicyBedrock-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:CreateGuardrail",
          "bedrock:DeleteGuardrail",
          "bedrock:GetGuardrail",
          "bedrock:ListGuardrails",
          "bedrock:ListTagsForResource",
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "deployer_policy_services" {
  role = aws_iam_role.deployer.name
  name = "DeployerPolicyServices-${var.platform_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "acm:*",
          "ecr:*",
          "elasticloadbalancing:*",
          "route53:*",
          "s3:*",
          "ssm:AddTagsToResource",
          "ssm:DeleteParameter",
          "ssm:DescribeParameters",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListTagsForResource",
          "ssm:PutParameter",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}