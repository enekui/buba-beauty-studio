################################################################################
# API Gateway HTTP — endpoint público (/subscribe, /confirm, /unsubscribe)
# + /admin/* con Cognito JWT authorizer.
################################################################################

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "API pública de suscripción + admin de campañas de Buba Beauty Studio."

  cors_configuration {
    allow_origins = var.cors_allowed_origins
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    expose_headers = ["Content-Type"]
    max_age        = 600
    allow_credentials = false
  }
}

resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = var.environment
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 20
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
      userAgent      = "$context.identity.userAgent"
    })
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = 14
}

################################################################################
# Cognito JWT authorizer
################################################################################

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.admin.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.admin.id}"
  }
}

################################################################################
# Integrations (Lambda proxy) + routes
################################################################################

resource "aws_apigatewayv2_integration" "subscribe" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.subscribe.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_integration" "confirm" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.confirm.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_integration" "unsubscribe" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.unsubscribe.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_integration" "send_campaign" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.send_campaign.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

# Routes públicas
resource "aws_apigatewayv2_route" "subscribe" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /subscribe"
  target    = "integrations/${aws_apigatewayv2_integration.subscribe.id}"
}

resource "aws_apigatewayv2_route" "confirm" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /confirm"
  target    = "integrations/${aws_apigatewayv2_integration.confirm.id}"
}

resource "aws_apigatewayv2_route" "unsubscribe" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /unsubscribe"
  target    = "integrations/${aws_apigatewayv2_integration.unsubscribe.id}"
}

# Routes admin (JWT Cognito)
resource "aws_apigatewayv2_route" "send_campaign" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /admin/campaigns"
  target             = "integrations/${aws_apigatewayv2_integration.send_campaign.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Permisos Lambda para APIGateway invoke
resource "aws_lambda_permission" "api_subscribe" {
  statement_id  = "AllowAPIInvokeSubscribe"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscribe.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_confirm" {
  statement_id  = "AllowAPIInvokeConfirm"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.confirm.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_unsubscribe" {
  statement_id  = "AllowAPIInvokeUnsubscribe"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.unsubscribe.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_campaign" {
  statement_id  = "AllowAPIInvokeCampaign"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.send_campaign.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
