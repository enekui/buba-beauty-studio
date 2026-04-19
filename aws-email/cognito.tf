################################################################################
# Cognito — User Pool + Hosted UI para el admin web
################################################################################

resource "random_string" "cognito_domain_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "aws_cognito_user_pool" "admin" {
  name = "${local.name_prefix}-admin"

  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Invitación — Admin de Buba Beauty Studio"
      email_message = <<-EOT
        <p>Hola,</p>
        <p>Has sido añadido como administrador del panel de email marketing de Buba Beauty Studio.</p>
        <p>Usuario: <strong>{username}</strong></p>
        <p>Contraseña temporal: <strong>{####}</strong></p>
        <p>Accede aquí: <a href="https://${local.admin_fqdn}">https://${local.admin_fqdn}</a></p>
      EOT
      sms_message   = "Buba Admin. Usuario: {username} - Contraseña temporal: {####}"
    }
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  deletion_protection = "ACTIVE"
}

resource "aws_cognito_user_pool_domain" "admin" {
  domain       = "${local.name_prefix}-admin-${random_string.cognito_domain_suffix.result}"
  user_pool_id = aws_cognito_user_pool.admin.id
}

resource "aws_cognito_user_pool_client" "admin" {
  name         = "${local.name_prefix}-admin-web"
  user_pool_id = aws_cognito_user_pool.admin.id

  generate_secret = false # SPA, no puede guardar secret

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  supported_identity_providers = ["COGNITO"]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  callback_urls = [
    "https://${local.admin_fqdn}/callback.html",
    "http://localhost:8080/callback.html", # desarrollo local
  ]
  logout_urls = [
    "https://${local.admin_fqdn}/",
    "http://localhost:8080/",
  ]

  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 60  # min
  id_token_validity      = 60  # min
  refresh_token_validity = 30  # días

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# Usuarios admin iniciales. El valor por defecto es lista vacía — si no
# se pasa ninguno, crear manualmente con `aws cognito-idp admin-create-user`.
resource "aws_cognito_user" "admin" {
  for_each = toset(var.admin_cognito_users)

  user_pool_id       = aws_cognito_user_pool.admin.id
  username           = each.value
  desired_delivery_mediums = ["EMAIL"]

  attributes = {
    email          = each.value
    email_verified = "true"
  }
}

# Output del domain (usado por outputs.tf principal).
output "cognito_hosted_ui_domain" {
  description = "Dominio Cognito para Hosted UI (login/signup)."
  value       = aws_cognito_user_pool_domain.admin.domain
}
