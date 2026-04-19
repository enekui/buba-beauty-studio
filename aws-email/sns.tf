################################################################################
# SNS — topics para SES bounces y complaints
#
# Cada topic recibe eventos del configuration set y dispara la Lambda
# bounce-complaint-handler, que suprime destinatarios problemáticos.
################################################################################

resource "aws_sns_topic" "ses_bounces" {
  name              = "${local.name_prefix}-ses-bounces"
  kms_master_key_id = aws_kms_key.main.arn

  tags = {
    Purpose = "SES bounces"
  }
}

resource "aws_sns_topic" "ses_complaints" {
  name              = "${local.name_prefix}-ses-complaints"
  kms_master_key_id = aws_kms_key.main.arn

  tags = {
    Purpose = "SES complaints"
  }
}

# Permitir que SES publique en los topics (event destination).
resource "aws_sns_topic_policy" "ses_bounces" {
  arn = aws_sns_topic.ses_bounces.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSESPublish"
      Effect    = "Allow"
      Principal = { Service = "ses.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.ses_bounces.arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_sns_topic_policy" "ses_complaints" {
  arn = aws_sns_topic.ses_complaints.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSESPublish"
      Effect    = "Allow"
      Principal = { Service = "ses.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.ses_complaints.arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# Suscripciones Lambda se definen en lambda.tf para evitar ciclo de
# dependencias (la Lambda necesita policy que permite recibir de SNS).
