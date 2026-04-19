################################################################################
# aws-email — main
#
# Stack AWS-native de email marketing para Buba Beauty Studio.
# Motor: SES v2 (Contact Lists + Templates + Suppression).
# Region: eu-west-1 (Irlanda, RGPD-friendly, baja latencia desde Galicia).
# ACM para CloudFront vive en us-east-1 (obligatorio para certificados
# asociados a distributions CloudFront).
################################################################################

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend S3 ya existe (bucket buba-terraform-state-372370374261 + tabla
  # buba-terraform-locks creados vía CLI) pero NO se activa aquí hasta que
  # el state sea reconstruido por imports — ver
  # .planning/phases/01-aws-email-hardening/STATE-LOSS-INCIDENT.md para el
  # plan de recuperación. Activar este bloque en ese momento.
  #
  # backend "s3" {
  #   bucket         = "buba-terraform-state-372370374261"
  #   key            = "aws-email/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "buba-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront exige ACM en us-east-1 para certificados asociados a distributions.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "aws-email"
    Owner       = "buba-beauty-studio"
    CostCenter  = "marketing"
  }

  # El MAIL FROM domain debe ser un subdominio del dominio principal
  # (RFC 7489) para que DMARC valide alineado.
  mail_from_domain = "mail.${var.root_domain}"

  admin_fqdn = "admin.${var.root_domain}"
}
