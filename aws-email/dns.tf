################################################################################
# DNS — Route53 records para autenticación de email
#
# Asume que la Hosted Zone pública del dominio raíz ya existe.
# Registros creados:
#   - 3× CNAME DKIM (autogenerados por SES, selectors rotan automáticamente)
#   - TXT SPF en el root domain
#   - TXT DMARC en _dmarc.<root>
#   - MX + TXT para el subdominio MAIL FROM (mail.<root>)
################################################################################

data "aws_route53_zone" "root" {
  name         = var.root_domain
  private_zone = false
}

# DKIM — SES v2 expone los 3 tokens en dkim_signing_attributes.tokens.
# Cada token es un selector; el registro es selectorN._domainkey.<root> CNAME
# selectorN.dkim.amazonses.com.
resource "aws_route53_record" "dkim" {
  count = 3

  zone_id = data.aws_route53_zone.root.zone_id
  name    = "${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.root_domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# SPF — amazonses incluye las IPs de envío. "-all" rechaza el resto.
# Si en el futuro se añade otro sender (ej. Google Workspace), ampliar el include.
resource "aws_route53_record" "spf" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = var.root_domain
  type    = "TXT"
  ttl     = 3600
  records = ["v=spf1 include:amazonses.com -all"]
}

# DMARC — arranca en p=none con reports. Subir a p=quarantine tras 2
# semanas limpias; después a p=reject.
resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "_dmarc.${var.root_domain}"
  type    = "TXT"
  ttl     = 3600
  records = [
    "v=DMARC1; p=${var.dmarc_policy}; rua=mailto:${var.dmarc_rua}; ruf=mailto:${var.dmarc_rua}; fo=1; adkim=s; aspf=s"
  ]
}

# MAIL FROM — records para que SES pueda enviar desde mail.<root>.
# Necesario para que DMARC alinee aspf=s (strict) sin romperse.
resource "aws_route53_record" "mail_from_mx" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.mail_from_domain
  type    = "MX"
  ttl     = 3600
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.mail_from_domain
  type    = "TXT"
  ttl     = 3600
  records = ["v=spf1 include:amazonses.com -all"]
}
