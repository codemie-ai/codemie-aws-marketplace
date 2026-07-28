locals {
  tags = merge(
    var.tags,
    {
      "user:tag" = var.platform_name
    },
  )
  cluster_name = var.platform_name
}

################################################################################
# Encryption key
################################################################################
module "ai_run_kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "4.2.0"

  region = var.region
  description                        = "AI Run key usage"
  key_usage                          = "ENCRYPT_DECRYPT"
  enable_key_rotation                = true
  rotation_period_in_days = 180
  aliases                            = ["airun-${replace(lower(local.cluster_name), "-", "")}"]

  key_administrators                 = [var.role_arn, var.eks_admin_role_arn]
  key_users = [module.ai_run_irsa.arn]

  tags = local.tags
}

################################################################################
# VPC
################################################################################
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, tomap({ "Name" = "codemie-nat" }))
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.platform_name

  create_vpc = true

  cidr            = var.platform_cidr
  azs             = var.subnet_azs
  private_subnets = var.private_cidrs
  public_subnets  = var.public_cidrs

  map_public_ip_on_launch    = false
  enable_dns_hostnames       = true
  enable_dns_support         = true
  enable_nat_gateway         = true
  single_nat_gateway         = true
  one_nat_gateway_per_az     = false
  manage_default_network_acl = false

  default_security_group_ingress = [
    {
      self = true
    }
  ]
  default_security_group_egress = [
    {
      self        = false
      cidr_blocks = "0.0.0.0/0"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
    }
  ]

  reuse_nat_ips       = true
  external_nat_ip_ids = [aws_eip.nat.id]
  tags                = local.tags
}

################################################################################
# DNS
################################################################################
module "codemie_dns_public" {
  source  = "terraform-aws-modules/route53/aws"
  version = "6.5.0"

  name        = var.platform_domain_name
  create_zone = false

  records = {
    all = {
      name = "*"
      type = "A"
      alias = {
        name    = module.alb.dns_name
        zone_id = module.alb.zone_id
      }
    }
  }
}

################################################################################
# ACM
################################################################################
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "6.3.0"

  domain_name = var.platform_domain_name
  zone_id     = module.codemie_dns_public.id

  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.platform_domain_name}",
  ]

  tags = merge(local.tags, tomap({ "Name" = var.platform_name }))
}

################################################################################
# ALB
################################################################################
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.0"

  name = "${var.platform_name}-ingress-alb"

  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets
  create_security_group      = false
  security_groups            = compact(concat(tolist([module.vpc.default_security_group_id]), var.security_group_ids))
  enable_http2               = false
  enable_deletion_protection = false

  listeners = {
    http-https-redirect = {
      port        = 80
      protocol    = "HTTP"
      action_type = "redirect"
      redirect = {
        port        = 443
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = var.ssl_policy
      certificate_arn = module.acm.acm_certificate_arn

      forward = {
        target_group_key = "https-instance"
      }
    }
  }

  target_groups = {
    http-instance = {
      name                 = "${var.platform_name}-infra-alb-http"
      port                 = 32080
      protocol             = "HTTP"
      deregistration_delay = 20
      create_attachment    = false

      health_check = {
        matcher = 404
      }
    }
    https-instance = {
      name                 = "${var.platform_name}-infra-alb-https"
      port                 = 32443
      protocol             = "HTTPS"
      deregistration_delay = 20
      create_attachment    = false

      health_check = {
        matcher = 404
      }
    }
  }
  idle_timeout = 500

  tags = local.tags
}

################################################################################
# EKS
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.0"

  enable_cluster_creator_admin_permissions = true

  name                   = local.cluster_name
  kubernetes_version     = var.cluster_version
  endpoint_public_access = true
  authentication_mode    = "API"

  create_iam_role               = true
  iam_role_use_name_prefix      = false
  iam_role_permissions_boundary = var.role_permissions_boundary_arn
  enable_auto_mode_custom_tags  = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_cloudwatch_log_group        = true
  enabled_log_types                  = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.eks_cluster_log_retention_days

  create_security_group              = false
  security_group_id                  = module.vpc.default_security_group_id
  create_node_security_group         = false
  create_primary_security_group_tags = false

  control_plane_scaling_config = {
    tier = var.eks_control_plane_scaling_tier
  }

  self_managed_node_groups = {
    worker_group_on_demand = {
      name = format("%s-%s", local.cluster_name, "on-demand")

      subnet_ids                    = module.vpc.private_subnets
      post_bootstrap_user_data      = var.add_userdata
      enable_monitoring             = false
      use_mixed_instances_policy    = true
      create_iam_instance_profile   = true
      min_size                      = var.demand_min_nodes_count
      max_size                      = var.demand_max_nodes_count
      desired_size                  = var.demand_desired_nodes_count
      ami_type                      = var.ami_type
      iam_role_use_name_prefix      = false
      iam_role_permissions_boundary = var.role_permissions_boundary_arn

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=normal'"

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = var.ebs_encrypt
            delete_on_termination = true
          }
        }
      }

      mixed_instances_policy = {
        launch_template = {
          override = var.demand_instance_types
        }
      }
    },
  }

  # OIDC Identity provider
  identity_providers = var.cluster_identity_providers

  # Addons
  addons = {
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = module.vpc_cni_irsa.arn
      configuration_values     = jsonencode({ enableNetworkPolicy = "true" })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.aws_ebs_csi_driver_irsa.arn
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    metrics-server = {
      most_recent = true
    }
  }

  access_entries = {
    ai-run-admin = {
      principal_arn = var.eks_admin_role_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = local.tags
}

resource "aws_autoscaling_attachment" "self_managed_asg_to_lb" {
  for_each = merge(
    { for name, tg in module.alb.target_groups : "alb-${name}" => tg.arn },
  )

  autoscaling_group_name = module.eks.self_managed_node_groups["worker_group_on_demand"].autoscaling_group_name
  lb_target_group_arn    = each.value
}

data "aws_caller_identity" "current" {}

################################################################################
# S3 Storage
################################################################################
module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "5.15.1"

  create_bucket = var.enable_codemie_s3_file_storage
  bucket        = "${lower(local.cluster_name)}-user-data-${data.aws_caller_identity.current.account_id}"
  acl           = "private"

  control_object_ownership = true
  object_ownership         = "ObjectWriter"
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
  attach_deny_insecure_transport_policy = true
  tags                                  = local.tags
}

################################################################################
# Elasticache (Valkey aka Redis)
################################################################################

resource "random_password" "cache_master_password" {
  length  = 64
  special = true
  lower   = true
  numeric = true

  min_lower   = 5
  min_upper   = 5
  min_numeric = 5
  min_special = 5

  override_special = "!&#$^<>-"
}

module "elasticache" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.11.1"

  replication_group_id = "${var.platform_name}-cache"

  engine         = "valkey"
  engine_version = "9.0"
  node_type      = "cache.t4g.small"

  transit_encryption_enabled = true
  auth_token                 = random_password.cache_master_password.result
  auth_token_update_strategy = "ROTATE"
  maintenance_window         = "sun:05:00-sun:09:00"
  apply_immediately          = true

  # Security Group
  vpc_id = module.vpc.vpc_id
  security_group_rules = {
    ingress_vpc = {
      # Default type is `ingress`
      # Default port is based on the default engine port
      description = "VPC traffic"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  # Subnet Group
  subnet_group_name        = "${var.platform_name}-cache"
  subnet_group_description = "Valkey replication group subnet group"
  subnet_ids               = module.vpc.private_subnets

  # Parameter Group
  create_parameter_group      = true
  parameter_group_name        = "${var.platform_name}-cache"
  parameter_group_family      = "valkey9"
  parameter_group_description = "Valkey replication group parameter group"
  parameters = [
    {
      name  = "latency-tracking"
      value = "yes"
    }
  ]

  tags = local.tags
}
