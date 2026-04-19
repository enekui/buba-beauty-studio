# Notas del reimport tras STATE-LOSS-INCIDENT

Fecha: 2026-04-19

## Resultado

- **97 de 98 recursos re-importados con éxito** vía `reimport.sh`.
- `terraform plan` final: `Plan: 1 to add, 14 to change, 0 to destroy`.
- **Zero destroys, zero replacements**. Los 14 `update in-place` son diffs cosméticos (defaults nulos, hashes de zip no deterministas, normalización de multiline strings) y son seguros de aplicar.

## Único recurso que no soporta import

### `aws_acm_certificate_validation.admin`

Terraform devuelve `resource aws_acm_certificate_validation doesn't support import`.
Es un recurso "de espera" sin state real en AWS (solo llama a la API de validación y espera a que el cert esté ISSUED). Al no poder importarse, terraform lo recreará en el próximo `apply`; como el cert ya está ISSUED la operación es idempotente y no afecta a la infra. El `Plan: 1 to add` corresponde a este recurso.

## Workarounds aplicados en el código

Se añadieron bloques `lifecycle { ignore_changes = [...] }` a tres recursos cuyo import arrastra diffs artificiales que forzarían replacement en cascada:

1. **`random_string.cognito_domain_suffix`** (`cognito.tf` líneas 5-22)
   - Import no permite fijar flags `lower/upper/numeric/special/length`; quedan con defaults (`special=true, upper=true`) que difieren de la config (`special=false, upper=false`).
   - El valor real `0nry6h` es válido bajo ambas configs, así que se ignoran los flags.
   - Sin este fix, el `random_string` se recreaba y forzaba replacement de `aws_cognito_user_pool_domain`, `aws_cognito_user_pool_client` y `aws_cognito_user`.

2. **`aws_cognito_user_pool_client.admin`** (`cognito.tf` alrededor de línea 118)
   - `generate_secret` es write-only en CreateUserPoolClient de AWS; terraform import no puede leerlo y lo deja null, forzando replacement.
   - Se ignora el diff; el cliente real es SPA sin secret (correcto según la config).

3. **`aws_cognito_user.admin["adianny@me.com"]`** (`cognito.tf` alrededor de línea 140)
   - El pool tiene `username_attributes = ["email"]`: AWS usa el email como alias pero internamente asigna un UUID como username real. El import trae el UUID al state y entra en conflicto con `username = each.value` (el email).
   - Se ignora `username` para evitar recreación del usuario (que dispararía reseteo de contraseña y email de invite duplicado).

## Cambios que el siguiente `apply` aplicará (todos seguros)

- `aws_acm_certificate_validation.admin` (nuevo, no-op).
- 6× `aws_lambda_function.*` — zips con hash diferente (esbuild es determinista pero zip tiene mtime). El código es el mismo; es solo un touch.
- `aws_cognito_user_pool.admin` — normalización whitespace del template HTML de invitación (equivalente funcionalmente).
- `aws_cognito_user.admin` — añade `desired_delivery_mediums = ["EMAIL"]` al state (ya coincide con la realidad).
- `aws_sesv2_configuration_set.main` — `tracking_options.https_policy` pasa de `"OPTIONAL"` (default AWS) a `null` (default terraform).
- `aws_sns_topic_subscription.{bounces,complaints}` — añade `confirmation_timeout_in_minutes=1` y `endpoint_auto_confirms=false` al state (defaults).
- `aws_kms_key.main` — añade `deletion_window_in_days=7` y `bypass_policy_lockout_safety_check=false` al state (defaults).
- `aws_cloudfront_function.admin_rewrite` — defaults.
- `aws_route53_record.acm_validation[...]` — añade `allow_overwrite=true` al state.

Ninguno supone un cambio real en AWS; son ajustes de state.

## Pasos siguientes recomendados

1. Ejecutar `terraform apply` para que el state absorba los defaults; el plan debería quedar en "No changes" tras eso (excepto los lambda zips, que seguirán mostrando diff mientras `source_code_hash` se derive del zip local — esto es inevitable sin un sistema de build reproducible).
2. Añadir a `.gitignore` el directorio `lambdas/dist/` y `lambdas/node_modules/` si no está ya (zips son artefactos de build).

## Lecciones aprendidas

- Antes de `git worktree remove --force` sobre un worktree con `terraform apply`, migrar el state a backend remoto **dentro** del mismo worktree.
- Varios recursos de terraform (cognito client `generate_secret`, random_string flags, cognito user con username_attributes, acm_certificate_validation) tienen limitaciones conocidas de import. Documentarlas en la plantilla base para futuros módulos evitará repetir este ciclo.
