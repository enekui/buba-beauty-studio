# aws-email — stack marketing AWS-native para Buba Beauty Studio

Módulo Terraform que monta un sistema de email marketing completo usando
**SES v2** como motor, con formulario público de suscripción, admin web
propio para lanzar campañas, gestión automática de bajas y bounces, y
observabilidad integrada. Coste objetivo: **< 2 USD/mes** para hasta ~5.000
contactos.

## Arquitectura

```
Cliente (web/app)
      │
      ▼
 API Gateway HTTP ── /subscribe  ──► Lambda subscribe   ──► SES SendEmail (confirm_opt_in)
                   ── /confirm    ──► Lambda confirm     ──► SES CreateContact (optIn=true)
                   ── /unsubscribe──► Lambda unsubscribe ──► SES UpdateContact (optedOut=true)
                   ── /admin/*    ──► JWT Cognito ──► Lambda send-campaign ──► SES SendBulkEmail
                                                                                  │
                                                                                  ▼
                                                                Configuration Set
                                                                           │
                                                     ┌─────────────────────┴────────────────────┐
                                                     ▼                                          ▼
                                              SNS ses-bounces                             SNS ses-complaints
                                                     │                                          │
                                                     └──────► Lambda bounce-complaint-handler ◄─┘
                                                                       │
                                                                       └─► PutSuppressedDestination
```

## Componentes

| Archivo | Qué define |
|---|---|
| `main.tf` | Providers AWS (eu-west-1 + us-east-1 alias para ACM), required_providers, locals, default_tags |
| `variables.tf` | Variables del módulo con validaciones |
| `outputs.tf` | URLs y IDs que el frontend y los scripts necesitan |
| `dns.tf` | Records Route53: TXT DMARC/SPF, 3x CNAME DKIM, MAIL FROM (MX+TXT) |
| `ses.tf` | Domain identity, configuration set, event destinations, contact list, suppression list |
| `sns.tf` | Topics ses-bounces y ses-complaints con suscripciones Lambda |
| `kms.tf` | Customer-managed key para encriptar secrets/tokens |
| `dynamodb.tf` | Tablas campaigns, sends_log, subscribe_tokens (free tier) |
| `cognito.tf` | User Pool admin + Hosted UI domain + app client |
| `api_gateway.tf` | HTTP API con rutas públicas + /admin JWT authorizer |
| `lambda.tf` | 5 funciones Node.js 20, IAM roles least-privilege, zip archives |
| `admin.tf` | S3 bucket admin + CloudFront + ACM (us-east-1) + Route53 alias |
| `budget.tf` | AWS Budgets monthly alert (desactivable con `budget_alert_email=""`) |
| `lambdas/*.mjs` | Código fuente de las 5 funciones Lambda |
| `templates/*.html` | Plantillas de email en la paleta cream/gold de Buba |

## Requisitos previos

- Terraform ≥ 1.6
- AWS CLI v2 configurada con credenciales con permisos sobre Route53, SES,
  API Gateway, Lambda, DynamoDB, SNS, Cognito, S3, CloudFront, ACM, KMS y
  Budgets.
- Zona Route53 pública para `bubabeautystudio.com` ya existente.
- Node.js 20+ (solo si quieres ejecutar los Lambdas en local).

## Bootstrap (primera vez)

```bash
cd aws-email
terraform init
terraform plan -out=plan.tfout
terraform apply plan.tfout
```

El apply tarda ~6 min (la mayor parte la emplea CloudFront en propagar).

Tras el primer apply, ver el output `next_steps` — contiene todos los
pasos manuales restantes (sandbox SES, admin user, plantillas, prueba
curl).

## Workflow diario

| Acción | Comando |
|---|---|
| Cambio de infra | `terraform plan && terraform apply` |
| Redesplegar Lambda tras editar código | `terraform apply -target=module.lambda` (o simplemente `apply`, detecta cambios en `archive_file`) |
| Redesplegar admin estático | `cd ../admin && ./deploy.sh` |
| Subir/actualizar plantilla de email | `aws sesv2 update-email-template --template-name monthly_promo --template-content file://templates/monthly_promo.json` |
| Crear usuario admin adicional | `aws cognito-idp admin-create-user --user-pool-id <id> --username <email>` |

## Salir del sandbox SES

Al empezar, SES limita el envío a direcciones verificadas y 200 emails/día.
Para poder enviar a clientas reales:

1. AWS Console → SES → *Account dashboard* → **Request production access**.
2. Justificación (copiar y pegar, ajustando):

   > We run email marketing for a beauty salon (Buba Beauty Studio,
   > A Coruña, Spain). All recipients opt-in via double-confirmation form
   > on our website. We use SES Contact Lists with automatic suppression,
   > process bounces/complaints within seconds via SNS+Lambda, and keep
   > complaint rate < 0.1%. Volume: 500-5000 emails/month initially.
   > Unsubscribe links are native (SES Contact List topic management).
   > DMARC, SPF, DKIM all configured with alignment.

3. Revisión AWS ~24-48h.

## Variables que conviene sobrescribir

Crear `terraform.tfvars` o pasar `-var`:

```hcl
admin_cognito_users = ["adianny@me.com", "buba@bubabeautystudio.com"]
budget_alert_email  = "adianny@me.com"
```

## Destrucción

```bash
terraform destroy
```

Cuidado: elimina la contact list y todos los contactos. Exportar antes
con `aws sesv2 list-contacts --contact-list-name <name> --output json > backup.json`.
