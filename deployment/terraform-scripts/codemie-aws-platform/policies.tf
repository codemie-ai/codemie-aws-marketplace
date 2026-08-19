data "aws_iam_policy_document" "ai_run_kms_policy" {
  version = "2012-10-17"

  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [
      "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:alias/airun-${replace(lower(local.cluster_name), "-", "")}",
    ]
  }
}

resource "aws_iam_policy" "ai_run_kms_policy" {
  name   = "AWSIRSA_${replace(title(local.cluster_name), "-", "")}_AI_RUN_KMS"
  policy = data.aws_iam_policy_document.ai_run_kms_policy.json

  tags = local.tags
}

data "aws_iam_policy_document" "ai_run_s3_policy" {
  version = "2012-10-17"

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${module.s3_bucket.s3_bucket_id}/*",
    ]
  }
}

resource "aws_iam_policy" "ai_run_s3_policy" {
  name   = "AWSIRSA_${replace(title(local.cluster_name), "-", "")}_AI_RUN_S3"
  policy = data.aws_iam_policy_document.ai_run_s3_policy.json

  tags = local.tags
}

data "aws_iam_policy_document" "ai_run_bedrock_policy" {
  version = "2012-10-17"

  statement {
    sid    = "BedrockInvokeModels"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:CountTokens"
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/anthropic.*",
      "arn:aws:bedrock:*::foundation-model/amazon.*",
      "arn:aws:bedrock:*::foundation-model/qwen.*",
      "arn:aws:bedrock:*::foundation-model/moonshotai.*"
    ]
  }

  statement {
    sid    = "BedrockCrossRegionInferenceProfiles"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:CountTokens",
    ]
    resources = [
      "arn:aws:bedrock:*:*:inference-profile/*.amazon.*",
      "arn:aws:bedrock:*:*:inference-profile/*.anthropic.*",
      "arn:aws:bedrock:*:*:inference-profile/qwen.*",
      "arn:aws:bedrock:*:*:inference-profile/moonshotai.*"
    ]
  }

  statement {
    sid    = "BedrockGuardrails"
    effect = "Allow"
    actions = [
      "bedrock:ApplyGuardrail",
      "bedrock:GetGuardrail",
      "bedrock:ListGuardrails",
    ]
    resources = [
      "arn:aws:bedrock:*:*:guardrail/*"
    ]
  }

  statement {
    sid    = "MarketplaceModelSubscriptions"
    effect = "Allow"
    actions = [
      "aws-marketplace:ViewSubscriptions",
      "aws-marketplace:Subscribe",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ai_run_bedrock_policy" {
  name   = "AWSIRSA_${replace(title(local.cluster_name), "-", "")}_AI_RUN_Bedrock"
  policy = data.aws_iam_policy_document.ai_run_bedrock_policy.json

  tags = local.tags
}
