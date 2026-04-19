################################################################################
# Outputs del módulo aws-email
################################################################################

output "api_base_url" {
  description = "URL base de la API Gateway. Usar para el formulario de la web pública y la app iOS."
  value       = aws_apigatewayv2_stage.api.invoke_url
}

output "subscribe_endpoint" {
  description = "Endpoint público para suscribirse al newsletter."
  value       = "${aws_apigatewayv2_stage.api.invoke_url}/subscribe"
}

output "admin_site_url" {
  description = "URL del panel admin (requiere login Cognito)."
  value       = "https://${local.admin_fqdn}"
}

output "cognito_hosted_ui_url" {
  description = "URL de login del Cognito Hosted UI para el admin."
  value       = "https://${aws_cognito_user_pool_domain.admin.domain}.auth.${var.aws_region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.admin.id}&response_type=code&redirect_uri=https%3A%2F%2F${local.admin_fqdn}%2Fcallback"
}

output "cognito_user_pool_id" {
  description = "ID del Cognito User Pool. Usar para crear admins adicionales vía AWS CLI."
  value       = aws_cognito_user_pool.admin.id
}

output "cognito_client_id" {
  description = "Client ID que el frontend admin usa para la PKCE flow."
  value       = aws_cognito_user_pool_client.admin.id
}

output "contact_list_name" {
  description = "Nombre de la SES Contact List principal."
  value       = aws_sesv2_contact_list.main.contact_list_name
}

output "ses_configuration_set" {
  description = "Nombre del configuration set SES (usar al enviar emails para activar tracking de eventos)."
  value       = aws_sesv2_configuration_set.main.configuration_set_name
}

output "dns_verification_status" {
  description = "Estado DKIM esperado. Se vuelve 'SUCCESS' cuando los 3 CNAMEs de DKIM propagan."
  value       = aws_sesv2_email_identity.domain.dkim_signing_attributes[0].status
}

output "cloudfront_admin_distribution_id" {
  description = "ID de la distribution CloudFront del admin. Usar para invalidaciones tras cada deploy."
  value       = aws_cloudfront_distribution.admin.id
}

output "admin_s3_bucket" {
  description = "Bucket S3 que sirve el admin static site."
  value       = aws_s3_bucket.admin.bucket
}

output "sns_bounce_topic_arn" {
  description = "ARN del topic SNS al que SES publica bounces."
  value       = aws_sns_topic.ses_bounces.arn
}

output "sns_complaint_topic_arn" {
  description = "ARN del topic SNS al que SES publica complaints."
  value       = aws_sns_topic.ses_complaints.arn
}

output "next_steps" {
  description = "Pasos manuales tras `terraform apply`."
  value = <<-EOT

    1. Verificar en SES Console que el dominio ${var.root_domain} aparece como "Verified".
       (Puede tardar ~5 min desde el apply mientras Route53 propaga.)

    2. Solicitar salida del sandbox SES:
       AWS Console → SES → Account Dashboard → Request production access.
       Indicar uso: marketing opt-in con doble confirmación, volumen esperado,
       política de baja automatizada, suppression list habilitada.

    3. Desplegar el admin web estático al bucket:
       cd admin && ./deploy.sh

    4. Crear al menos un admin (si no se usó var.admin_cognito_users):
       aws cognito-idp admin-create-user \
         --user-pool-id ${aws_cognito_user_pool.admin.id} \
         --username adianny@me.com \
         --user-attributes Name=email,Value=adianny@me.com Name=email_verified,Value=true

    5. Subir plantillas SES desde aws-email/templates/:
       for t in confirm_opt_in monthly_promo new_service; do
         aws sesv2 create-email-template \
           --template-name "$t" \
           --template-content file://templates/"$t".json
       done

    6. Probar con curl:
       curl -X POST ${aws_apigatewayv2_stage.api.invoke_url}/subscribe \
         -H 'Content-Type: application/json' \
         -d '{"email":"tu-email@ejemplo.com","consent":true}'
  EOT
}
