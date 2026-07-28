moved {
  from = module.ai_run_irsa.aws_iam_role_policy_attachment.this["AIRunKMSPolicy"]
  to   = module.ai_run_irsa.aws_iam_role_policy_attachment.additional["AIRunKMSPolicy"]
}

moved {
  from = module.ai_run_irsa.aws_iam_role_policy_attachment.this["AIRunS3Policy"]
  to   = module.ai_run_irsa.aws_iam_role_policy_attachment.additional["AIRunS3Policy"]
}

moved {
  from = module.ai_run_irsa.aws_iam_role_policy_attachment.this["AIRunBedrockPolicy"]
  to   = module.ai_run_irsa.aws_iam_role_policy_attachment.additional["AIRunBedrockPolicy"]
}

moved {
  from = module.aws_ebs_csi_driver_irsa.aws_iam_role_policy_attachment.this["AmazonEBSCSIDriverPolicy"]
  to   = module.aws_ebs_csi_driver_irsa.aws_iam_role_policy_attachment.additional["AmazonEBSCSIDriverPolicy"]
}

moved {
  from = module.records.aws_route53_record.this["* A"]
  to   = module.codemie_dns_public.aws_route53_record.this["all"]
}
