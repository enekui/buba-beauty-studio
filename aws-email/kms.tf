################################################################################
# KMS — customer-managed key para encriptar en reposo secretos del stack
#
# Se usa en:
#   - DynamoDB tables (tokens y campaigns pueden contener emails)
#   - SNS topics (mensajes de bounces con emails reales)
#   - Cognito (backup encryption)
################################################################################

resource "aws_kms_key" "main" {
  description             = "Customer-managed key del stack aws-email (${local.name_prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowAWSServicesUse"
        Effect    = "Allow"
        Principal = {
          Service = [
            "sns.amazonaws.com",
            "ses.amazonaws.com",
            "dynamodb.amazonaws.com",
            "logs.${var.aws_region}.amazonaws.com",
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}

data "aws_caller_identity" "current" {}
