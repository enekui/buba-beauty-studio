################################################################################
# SES v2 — Domain identity, configuration set, contact list, suppression
################################################################################

# Identidad de dominio. DKIM Easy (RSA-2048 rotado por AWS automáticamente).
resource "aws_sesv2_email_identity" "domain" {
  email_identity = var.root_domain

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

# MAIL FROM alineado para DMARC strict (aspf=s).
resource "aws_sesv2_email_identity_mail_from_attributes" "domain" {
  email_identity         = aws_sesv2_email_identity.domain.email_identity
  mail_from_domain       = local.mail_from_domain
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"

  depends_on = [
    aws_route53_record.mail_from_mx,
    aws_route53_record.mail_from_spf,
  ]
}

# Configuration set: activa reputation metrics y publica eventos en SNS.
resource "aws_sesv2_configuration_set" "main" {
  configuration_set_name = "${local.name_prefix}-main"

  delivery_options {
    tls_policy = "REQUIRE"
  }

  reputation_options {
    reputation_metrics_enabled = true
  }

  sending_options {
    sending_enabled = true
  }

  suppression_options {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }

  tracking_options {
    custom_redirect_domain = var.root_domain
  }

  vdm_options {
    dashboard_options {
      engagement_metrics = "ENABLED"
    }

    guardian_options {
      optimized_shared_delivery = "ENABLED"
    }
  }
}

# Event destinations: bounces y complaints a SNS; entregas agregadas a CloudWatch.
resource "aws_sesv2_configuration_set_event_destination" "sns_bounces" {
  configuration_set_name = aws_sesv2_configuration_set.main.configuration_set_name
  event_destination_name = "sns-bounces"

  event_destination {
    enabled              = true
    matching_event_types = ["BOUNCE"]

    sns_destination {
      topic_arn = aws_sns_topic.ses_bounces.arn
    }
  }
}

resource "aws_sesv2_configuration_set_event_destination" "sns_complaints" {
  configuration_set_name = aws_sesv2_configuration_set.main.configuration_set_name
  event_destination_name = "sns-complaints"

  event_destination {
    enabled              = true
    matching_event_types = ["COMPLAINT"]

    sns_destination {
      topic_arn = aws_sns_topic.ses_complaints.arn
    }
  }
}

resource "aws_sesv2_configuration_set_event_destination" "cw_metrics" {
  configuration_set_name = aws_sesv2_configuration_set.main.configuration_set_name
  event_destination_name = "cw-metrics"

  event_destination {
    enabled              = true
    matching_event_types = ["SEND", "DELIVERY", "OPEN", "CLICK", "REJECT"]

    cloud_watch_destination {
      dimension_configuration {
        default_dimension_value = "default"
        dimension_name          = "ses:configuration-set"
        dimension_value_source  = "MESSAGE_TAG"
      }
    }
  }
}

# Contact list única con 1 topic "promociones".
# Añadir más topics en el futuro (ej. "eventos") es cuestión de extender
# aquí el bloque topic — SES soporta hasta 20 por lista.
resource "aws_sesv2_contact_list" "main" {
  contact_list_name = "${local.name_prefix}-marketing"
  description       = "Lista principal de marketing de Buba Beauty Studio."

  topic {
    topic_name                 = var.contact_list_topic_name
    display_name               = var.contact_list_topic_display_name
    description                = "Novedades, promociones mensuales y nuevos servicios."
    default_subscription_status = "OPT_IN"
  }
}
