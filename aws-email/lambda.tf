################################################################################
# Lambda — 5 handlers Node.js 20 (ESM .mjs)
#
# El build externo (lambdas/build.sh) debe ejecutarse antes de `terraform
# apply` para generar lambdas/dist/<name>.zip. Terraform detecta el hash
# del zip y redesplega al cambiar el código.
################################################################################

locals {
  lambda_runtime = "nodejs20.x"
  lambda_arch    = "arm64" # 20% más barato que x86 para el mismo perf
  lambda_dist    = "${path.module}/lambdas/dist"

  lambda_env_common = {
    CONTACT_LIST_NAME       = aws_sesv2_contact_list.main.contact_list_name
    CONFIGURATION_SET_NAME  = aws_sesv2_configuration_set.main.configuration_set_name
    SENDER_FROM_EMAIL       = var.sender_from_email
    SENDER_FROM_NAME        = var.sender_from_name
    REPLY_TO_EMAIL          = var.reply_to_email
    TOKENS_TABLE_NAME       = aws_dynamodb_table.subscribe_tokens.name
    CAMPAIGNS_TABLE_NAME    = aws_dynamodb_table.campaigns.name
    SENDS_LOG_TABLE_NAME    = aws_dynamodb_table.sends_log.name
    CONFIRM_BASE_URL        = "${aws_apigatewayv2_stage.api.invoke_url}"
    ROOT_DOMAIN             = var.root_domain
    CONFIRM_TEMPLATE_NAME   = "confirm_opt_in"
    TOPIC_NAME              = var.contact_list_topic_name
    CORS_ALLOWED_ORIGINS    = join(",", var.cors_allowed_origins)
  }
}

################################################################################
# IAM role compartido (mínimo permiso por función via inline policies)
################################################################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_subscribe" {
  name_prefix        = "${local.name_prefix}-sub-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_confirm" {
  name_prefix        = "${local.name_prefix}-cnf-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_unsubscribe" {
  name_prefix        = "${local.name_prefix}-uns-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_bounce" {
  name_prefix        = "${local.name_prefix}-bnc-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_campaign" {
  name_prefix        = "${local.name_prefix}-cmp-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Basic execution + X-Ray a todas las funciones.
resource "aws_iam_role_policy_attachment" "basic_exec" {
  for_each = {
    subscribe   = aws_iam_role.lambda_subscribe.name
    confirm     = aws_iam_role.lambda_confirm.name
    unsubscribe = aws_iam_role.lambda_unsubscribe.name
    bounce      = aws_iam_role.lambda_bounce.name
    campaign    = aws_iam_role.lambda_campaign.name
  }

  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policies mínimas por función.

resource "aws_iam_role_policy" "subscribe" {
  role = aws_iam_role.lambda_subscribe.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.subscribe_tokens.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendTemplatedEmail",
          "ses:GetContact",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.main.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "confirm" {
  role = aws_iam_role.lambda_confirm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.subscribe_tokens.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ses:CreateContact", "ses:UpdateContact", "ses:GetContact"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.main.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "unsubscribe" {
  role = aws_iam_role.lambda_unsubscribe.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ses:UpdateContact",
        "ses:GetContact",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "bounce" {
  role = aws_iam_role.lambda_bounce.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:PutSuppressedDestination"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.sends_log.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.main.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "campaign" {
  role = aws_iam_role.lambda_campaign.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendBulkEmail",
          "ses:SendEmail",
          "ses:ListContacts",
          "ses:CreateEmailTemplate",
          "ses:UpdateEmailTemplate",
          "ses:DeleteEmailTemplate",
          "ses:GetEmailTemplate",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
        ]
        Resource = [
          aws_dynamodb_table.campaigns.arn,
          "${aws_dynamodb_table.campaigns.arn}/index/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.main.arn
      },
    ]
  })
}

################################################################################
# Funciones Lambda
################################################################################

resource "aws_lambda_function" "subscribe" {
  function_name = "${local.name_prefix}-subscribe"
  role          = aws_iam_role.lambda_subscribe.arn
  runtime       = local.lambda_runtime
  architectures = [local.lambda_arch]
  handler       = "subscribe.handler"

  filename         = "${local.lambda_dist}/subscribe.zip"
  source_code_hash = filebase64sha256("${local.lambda_dist}/subscribe.zip")

  timeout     = 10
  memory_size = 256

  environment {
    variables = local.lambda_env_common
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "confirm" {
  function_name = "${local.name_prefix}-confirm"
  role          = aws_iam_role.lambda_confirm.arn
  runtime       = local.lambda_runtime
  architectures = [local.lambda_arch]
  handler       = "confirm.handler"

  filename         = "${local.lambda_dist}/confirm.zip"
  source_code_hash = filebase64sha256("${local.lambda_dist}/confirm.zip")

  timeout     = 10
  memory_size = 256

  environment {
    variables = local.lambda_env_common
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "unsubscribe" {
  function_name = "${local.name_prefix}-unsubscribe"
  role          = aws_iam_role.lambda_unsubscribe.arn
  runtime       = local.lambda_runtime
  architectures = [local.lambda_arch]
  handler       = "unsubscribe.handler"

  filename         = "${local.lambda_dist}/unsubscribe.zip"
  source_code_hash = filebase64sha256("${local.lambda_dist}/unsubscribe.zip")

  timeout     = 10
  memory_size = 256

  environment {
    variables = local.lambda_env_common
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "bounce_complaint_handler" {
  function_name = "${local.name_prefix}-bounce-complaint"
  role          = aws_iam_role.lambda_bounce.arn
  runtime       = local.lambda_runtime
  architectures = [local.lambda_arch]
  handler       = "bounce-complaint-handler.handler"

  filename         = "${local.lambda_dist}/bounce-complaint-handler.zip"
  source_code_hash = filebase64sha256("${local.lambda_dist}/bounce-complaint-handler.zip")

  timeout     = 20
  memory_size = 256

  environment {
    variables = local.lambda_env_common
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "send_campaign" {
  function_name = "${local.name_prefix}-send-campaign"
  role          = aws_iam_role.lambda_campaign.arn
  runtime       = local.lambda_runtime
  architectures = [local.lambda_arch]
  handler       = "send-campaign.handler"

  filename         = "${local.lambda_dist}/send-campaign.zip"
  source_code_hash = filebase64sha256("${local.lambda_dist}/send-campaign.zip")

  timeout     = 300 # chunks de 50 sobre 5k contactos pueden tardar
  memory_size = 512

  environment {
    variables = local.lambda_env_common
  }

  tracing_config {
    mode = "Active"
  }
}

################################################################################
# SNS subscriptions → Lambda bounce-complaint-handler
################################################################################

resource "aws_sns_topic_subscription" "bounces" {
  topic_arn = aws_sns_topic.ses_bounces.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.bounce_complaint_handler.arn
}

resource "aws_sns_topic_subscription" "complaints" {
  topic_arn = aws_sns_topic.ses_complaints.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.bounce_complaint_handler.arn
}

resource "aws_lambda_permission" "sns_bounces" {
  statement_id  = "AllowSNSInvokeBounces"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bounce_complaint_handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ses_bounces.arn
}

resource "aws_lambda_permission" "sns_complaints" {
  statement_id  = "AllowSNSInvokeComplaints"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bounce_complaint_handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ses_complaints.arn
}

################################################################################
# CloudWatch Log retention (14 días — ahorra coste)
################################################################################

resource "aws_cloudwatch_log_group" "subscribe" {
  name              = "/aws/lambda/${aws_lambda_function.subscribe.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "confirm" {
  name              = "/aws/lambda/${aws_lambda_function.confirm.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "unsubscribe" {
  name              = "/aws/lambda/${aws_lambda_function.unsubscribe.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "bounce" {
  name              = "/aws/lambda/${aws_lambda_function.bounce_complaint_handler.function_name}"
  retention_in_days = 30 # más para investigar complaints
}

resource "aws_cloudwatch_log_group" "campaign" {
  name              = "/aws/lambda/${aws_lambda_function.send_campaign.function_name}"
  retention_in_days = 30
}
