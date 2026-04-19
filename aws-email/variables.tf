################################################################################
# Variables del módulo aws-email
################################################################################

variable "project" {
  description = "Identificador corto del proyecto, se usa como prefijo de recursos."
  type        = string
  default     = "buba"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.project))
    error_message = "El nombre del proyecto debe empezar por letra minúscula, contener sólo [a-z0-9-] y tener 2-25 caracteres."
  }
}

variable "environment" {
  description = "Entorno lógico del stack (prod, staging, dev)."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment debe ser uno de: prod, staging, dev."
  }
}

variable "aws_region" {
  description = "Región AWS primaria donde se despliega el stack (todo excepto el cert ACM)."
  type        = string
  default     = "eu-west-1"
}

variable "root_domain" {
  description = "Dominio raíz gestionado en Route53 (ej. bubabeautystudio.com). Debe existir ya una Hosted Zone pública con este nombre."
  type        = string
  default     = "bubabeautystudio.com"
}

variable "sender_from_email" {
  description = "Dirección From que aparece en los emails (debe ser del dominio verificado)."
  type        = string
  default     = "hola@bubabeautystudio.com"
}

variable "sender_from_name" {
  description = "Nombre para mostrar en el campo From."
  type        = string
  default     = "Buba Beauty Studio"
}

variable "reply_to_email" {
  description = "Dirección Reply-To para respuestas directas de las clientas."
  type        = string
  default     = "hola@bubabeautystudio.com"
}

variable "dmarc_rua" {
  description = "Dirección a la que se envían reportes agregados de DMARC."
  type        = string
  default     = "dmarc@bubabeautystudio.com"
}

variable "dmarc_policy" {
  description = "Política DMARC inicial. Se recomienda arrancar en 'none' y escalar a 'quarantine' tras 2 semanas limpias."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "quarantine", "reject"], var.dmarc_policy)
    error_message = "dmarc_policy debe ser none, quarantine o reject."
  }
}

variable "contact_list_topic_name" {
  description = "Nombre del topic SES al que se suscriben las clientas (visible en el link de baja)."
  type        = string
  default     = "promociones"
}

variable "contact_list_topic_display_name" {
  description = "Texto que se muestra al destinatario en el link de gestión de preferencias."
  type        = string
  default     = "Promociones y novedades de Buba Beauty Studio"
}

variable "admin_cognito_users" {
  description = "Lista de emails que tendrán cuenta de admin en el panel web (Cognito User Pool). Se crean desactivados; AWS envía el email de invitación con contraseña temporal."
  type        = list(string)
  default     = []
}

variable "cors_allowed_origins" {
  description = "Orígenes permitidos por CORS en la API de suscripción (web pública + admin)."
  type        = list(string)
  default     = [
    "https://bubabeautystudio.com",
    "https://www.bubabeautystudio.com",
    "https://admin.bubabeautystudio.com",
  ]
}

variable "budget_alert_email" {
  description = "Email que recibe las alertas de coste del stack (AWS Budgets). Vacío desactiva el budget."
  type        = string
  default     = ""
}

variable "budget_monthly_usd" {
  description = "Umbral mensual en USD sobre el que dispara la alerta de AWS Budgets."
  type        = number
  default     = 5
}
