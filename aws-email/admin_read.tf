################################################################################
# Admin-read Lambda + rutas (GET /admin/campaigns, GET /admin/audience/count)
#
# Separado de lambda.tf para dejar claro el scope: solo lectura, sin
# modificar contactos ni enviar emails. El admin web lo usa para
# alimentar el listado de campañas y el contador de audiencia del
# diálogo de confirmación.
################################################################################

resource "aws_iam_role" "lambda_admin_read" {
  name_prefix        = "${local.name_prefix}-adr-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "admin_read_basic_exec" {
  role       = aws_iam_role.lambda_admin_read.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "admin_read" {
  role = aws_iam_role.lambda_admin_read.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:ListContacts"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
        ]
        Resource = [
          aws_dynamodb_table.campaigns.arn,
          "${aws_dynamodb_table.campaigns.arn}/index/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.main.arn
      },
    ]
  })
}

resource "aws_lambda_function" "admin_read" {
  function_name = "${local.name_prefix}-admin-read"
  role          = aws_iam_role.lambda_admin_read.arn
  runtime       = local.lambda_runtime
  architectures = [local.lambda_arch]
  handler       = "admin-read.handler"

  filename         = "${local.lambda_dist}/admin-read.zip"
  source_code_hash = filebase64sha256("${local.lambda_dist}/admin-read.zip")

  timeout     = 15
  memory_size = 256

  environment {
    variables = local.lambda_env_common
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "admin_read" {
  name              = "/aws/lambda/${aws_lambda_function.admin_read.function_name}"
  retention_in_days = 14
}

################################################################################
# API Gateway — integración + rutas /admin/* de lectura
################################################################################

resource "aws_apigatewayv2_integration" "admin_read" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.admin_read.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 15000
}

resource "aws_apigatewayv2_route" "admin_campaigns_list" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /admin/campaigns"
  target             = "integrations/${aws_apigatewayv2_integration.admin_read.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "admin_audience_count" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /admin/audience/count"
  target             = "integrations/${aws_apigatewayv2_integration.admin_read.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "api_admin_read" {
  statement_id  = "AllowAPIInvokeAdminRead"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_read.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
