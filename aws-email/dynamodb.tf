################################################################################
# DynamoDB — tablas auxiliares (todas pay-per-request, free tier cubre el uso)
################################################################################

# Tokens pendientes de doble opt-in. TTL 72h, se purgan solas.
resource "aws_dynamodb_table" "subscribe_tokens" {
  name         = "${local.name_prefix}-subscribe-tokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "token"

  attribute {
    name = "token"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  point_in_time_recovery {
    enabled = false # sin PITR, son tokens efímeros
  }
}

# Audit log de campañas lanzadas. Sin TTL, histórico permanente.
resource "aws_dynamodb_table" "campaigns" {
  name         = "${local.name_prefix}-campaigns"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "campaignId"
  range_key    = "createdAt"

  attribute {
    name = "campaignId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # GSI para listar campañas por orden cronológico inverso en el admin.
  attribute {
    name = "topic"
    type = "S"
  }

  global_secondary_index {
    name            = "topic-createdAt-index"
    hash_key        = "topic"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  point_in_time_recovery {
    enabled = true
  }
}

# Log per-destinatario: bounces, complaints, envíos individuales.
# TTL 90 días — suficiente para debugging y cumple RGPD.
resource "aws_dynamodb_table" "sends_log" {
  name         = "${local.name_prefix}-sends-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "recipientEmail"
  range_key    = "sk"

  attribute {
    name = "recipientEmail"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  point_in_time_recovery {
    enabled = false
  }
}
