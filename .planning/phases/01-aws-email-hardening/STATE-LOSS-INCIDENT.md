# Incidente: pérdida del Terraform state de `aws-email/`

**Fecha:** 2026-04-19
**Severidad:** Media — infra viva no afectada, pero Terraform ya no la gestiona.

## Qué ocurrió

1. El primer `terraform apply` de `aws-email/` se ejecutó en el worktree `../buba-beauty-studio-worktree-aws-email`. El state local (`terraform.tfstate`) y el directorio `.terraform/` quedaron en ese worktree.
2. Al terminar el sprint inicial, el worktree se eliminó con `git worktree remove --force` (paso de "limpieza absoluta" del workflow).
3. `--force` borra archivos no trackeados por Git, y `terraform.tfstate` está en `.gitignore` → se perdió el state junto con el worktree.
4. Al arrancar el plan 01-01 (migración a backend remoto), al llegar al `terraform init -migrate-state` no había state que migrar: empezaría con un state vacío apuntando a 98 recursos reales que ya existen, y el siguiente `plan` propondría recrearlos (lo cual fallaría por nombres únicos colisionando).

## Estado actual

- **Infra AWS: 100% operativa**. Admin site en `admin.bubabeautystudio.com`, SES Contact List + templates + Lambdas + Cognito + CloudFront + Route53 — todo sigue funcionando como el día del deploy.
- **Bucket S3 de state vacío**: `buba-terraform-state-372370374261` creado en Task 1 del plan 01-01, sin objetos dentro.
- **Tabla DynamoDB vacía**: `buba-terraform-locks` creada, sin locks.
- **main.tf revertido**: el bloque `backend "s3"` volvió a comentarse para que nadie dispare un init vacío contra el bucket.
- **Recursos huérfanos**: los 98 recursos del módulo no están bajo control de ningún state. Cualquier cambio a la infra hay que hacerlo vía AWS Console / CLI hasta que el state se reconstruya.

## Plan de recuperación (para una sesión dedicada)

**Objetivo**: reconstruir el state mediante `terraform import` para cada recurso, de forma que al cerrar el proceso `terraform plan` diga "No changes".

### Prereqs

- AWS CLI con credenciales del account 372370374261.
- Terraform 1.6+.
- ~2 horas dedicadas.

### Pasos

1. **Backup de la intención actual**: `cp -r aws-email aws-email.pre-import-backup/` antes de tocar nada.

2. **Activar backend remoto**: descomentar el bloque `backend "s3"` en `main.tf`.

3. **`terraform init`** en `aws-email/`. Al no haber state local ni remoto, arrancará vacío.

4. **Script de imports**: crear `aws-email/reimport.sh` que ejecute `terraform import <resource_address> <id>` para cada uno de los 98 recursos. Mapeo:

| Resource address | How to get ID |
|---|---|
| `aws_sesv2_email_identity.domain` | `bubabeautystudio.com` |
| `aws_sesv2_configuration_set.main` | `buba-prod-main` |
| `aws_sesv2_contact_list.main` | `buba-prod-marketing` |
| `aws_sns_topic.ses_bounces` | `arn:aws:sns:eu-west-1:372370374261:buba-prod-ses-bounces` |
| `aws_sns_topic.ses_complaints` | idem con `-ses-complaints` |
| `aws_kms_key.main` | `aws kms list-aliases --query 'Aliases[?AliasName==\`alias/buba-prod\`].TargetKeyId' --output text` |
| `aws_dynamodb_table.subscribe_tokens` / `campaigns` / `sends_log` | nombres `buba-prod-*` |
| `aws_cognito_user_pool.admin` | `eu-west-1_SHRKcryaZ` |
| `aws_cognito_user_pool_client.admin` | `<pool_id>/<client_id>` → `eu-west-1_SHRKcryaZ/7344v1aa2bi9vvjldqtu650g6j` |
| `aws_cognito_user_pool_domain.admin` | `buba-prod-admin-0nry6h` |
| `aws_apigatewayv2_api.main` | `81mmdkibg8` |
| `aws_apigatewayv2_stage.api` | `81mmdkibg8/prod` |
| `aws_lambda_function.*` | function name (`buba-prod-subscribe`, etc.) |
| `aws_iam_role.*` | role name (`buba-prod-sub-20260419...`) — listar con `aws iam list-roles --query 'Roles[?starts_with(RoleName, \`buba-prod-\`)].RoleName'` |
| `aws_cloudwatch_log_group.*` | log group name (`/aws/lambda/buba-prod-...`) |
| `aws_s3_bucket.admin` | `buba-prod-admin-372370374261` |
| `aws_cloudfront_distribution.admin` | `E2ZSGJELCJFZJI` |
| `aws_cloudfront_origin_access_control.admin` | `E39P63G9EWFPFX` |
| `aws_acm_certificate.admin` | ARN en us-east-1 via `aws acm list-certificates --region us-east-1` |
| `aws_route53_record.*` | `<zone_id>_<name>_<type>` — listar con `aws route53 list-resource-record-sets --hosted-zone-id Z06668016LU3R26NZSQH` |
| `aws_budgets_budget.monthly[0]` | `<account_id>:<budget_name>` = `372370374261:buba-prod-monthly` |

5. **Ejecutar `reimport.sh`**. Si alguno falla por falta de permisos o por recurso ambiguo, debuggear uno a uno.

6. **`terraform plan`** — debería devolver **"No changes"**. Si propone cambios, investigar cada diff (a veces son tags que AWS añadió automáticamente o default values que hay que alinear).

7. **Commit**: `git add aws-email/main.tf && git commit -m "aws-email: activar backend S3 tras reimport del state"`.

### Alternativa: "start fresh"

Si el reimport es demasiado doloroso, la alternativa limpia es:

1. `terraform destroy` NO funciona sin state.
2. Borrar manualmente los 98 recursos via AWS Console / CLI (cuidado con el orden de dependencias).
3. `terraform apply` desde cero contra el nuevo backend S3.

**Coste**: ~15-30 min de downtime del admin site + re-envío del Cognito admin invite. El formulario público quedaría temporalmente roto porque la API Gateway tendría un ID diferente; habría que actualizar `index.html` con el nuevo URL tras el apply.

## Lección aprendida

Antes de `git worktree remove --force` en un worktree que haya ejecutado `terraform apply`, hacer UNA de estas:

1. **Mover el state al repo principal**: `mv <worktree>/aws-email/terraform.tfstate* <main-repo>/aws-email/`.
2. **O migrar a backend remoto ANTES de destruir el worktree**: ejecutar el plan 01-01 dentro del worktree mismo, no en una sesión posterior.
3. **O verificar que `.gitignore` no tenga `*.tfstate` si se quiere forzar commit** (no recomendado por seguridad: el state puede contener secretos).

La opción 2 es la más limpia y debería ser default en futuros proyectos: "si vas a crear un worktree para Terraform, migra el state a remoto antes del primer apply".
