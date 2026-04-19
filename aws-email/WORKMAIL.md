# WorkMail — `info@bubabeautystudio.com`

Buzón oficial del negocio gestionado con **Amazon WorkMail** en eu-west-1.

## Datos operativos

| Concepto | Valor |
|---|---|
| Organization ID | `m-d5bde89b64194df8814b016c13823c11` |
| Organization alias | `buba` |
| Region | `eu-west-1` |
| Default mail domain | `bubabeautystudio.com` |
| Usuario principal | `info@bubabeautystudio.com` |
| Webmail | `https://buba.awsapps.com/mail` |
| IMAP | `imap.mail.eu-west-1.awsapps.com` · port 993 · SSL |
| SMTP | `smtp.mail.eu-west-1.awsapps.com` · port 465 · SSL |
| Coste | ~4 USD/usuario/mes |

La contraseña temporal del usuario `info` se generó al crear la cuenta y se
guardó en `~/.claude/secrets/buba-workmail-info.txt` (permisos `600`, NO en
el repo). Al primer login WorkMail pide cambiarla.

## Qué hay bajo control Terraform

Los registros DNS en Route53 (ver `dns.tf`):

- `MX bubabeautystudio.com → 10 inbound-smtp.eu-west-1.amazonaws.com`
- `TXT _amazonses.bubabeautystudio.com` (token de verificación de dominio)
- `CNAME autodiscover.bubabeautystudio.com → autodiscover.mail.eu-west-1.awsapps.com`

Los 3 DKIM CNAMEs ya existían para SES — WorkMail reutiliza las mismas
identities SES, no necesita DKIM adicional.

## Qué NO está bajo control Terraform

El AWS provider no expone todavía recursos `aws_workmail_*`, así que estos
pasos son **manuales** (documentados para reproducibilidad):

### Bootstrap desde cero

```bash
REGION=eu-west-1

# 1. Crear organización
aws workmail create-organization --alias buba --region $REGION
# Esperar ~30-60s hasta State=Active
# Anotar el OrganizationId devuelto.

# 2. Registrar dominio
ORG=<OrganizationId>
aws workmail register-mail-domain --organization-id $ORG --domain-name bubabeautystudio.com --region $REGION

# 3. Registros DNS (ya los mete Terraform via dns.tf, solo aplicar)
cd aws-email && terraform apply

# 4. Setear como dominio por defecto
aws workmail update-default-mail-domain --organization-id $ORG --domain-name bubabeautystudio.com --region $REGION

# 5. Crear usuario info
TMP_PW=$(python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits+'!@#%^&*') for _ in range(16)))")
USER_OUT=$(aws workmail create-user --organization-id $ORG --region $REGION \
  --name info \
  --display-name "Buba Beauty Studio" \
  --password "$TMP_PW" \
  --first-name "Buba" --last-name "Beauty Studio")
USER_ID=$(echo "$USER_OUT" | jq -r '.UserId')

# 6. Registrar email al usuario
aws workmail register-to-work-mail --organization-id $ORG --entity-id $USER_ID --email "info@bubabeautystudio.com" --region $REGION

# 7. Guardar credenciales en un archivo local (NO en el repo)
# La password temporal se pierde si no se captura; si se pierde, resetear con
# aws workmail reset-password --organization-id $ORG --user-id $USER_ID --password <new>
```

### Operaciones comunes

```bash
ORG=m-d5bde89b64194df8814b016c13823c11
REGION=eu-west-1

# Listar usuarios
aws workmail list-users --organization-id $ORG --region $REGION

# Reset de password de un usuario
aws workmail reset-password --organization-id $ORG --user-id <USER_ID> --password "<new-strong-password>" --region $REGION

# Añadir un usuario adicional (ej. empleada)
aws workmail create-user --organization-id $ORG --region $REGION --name <username> --display-name "..." --password "..." --first-name "..." --last-name "..."
aws workmail register-to-work-mail --organization-id $ORG --entity-id <USER_ID> --email "<username>@bubabeautystudio.com" --region $REGION

# Desactivar un usuario (deja de recibir emails pero preserva el buzón)
aws workmail deregister-from-work-mail --organization-id $ORG --entity-id <USER_ID> --region $REGION
```

## Coexistencia con SES marketing

- **SES sigue enviando** marketing outbound desde `hola@` (configured en `variables.tf`).
- **WorkMail recibe todo lo apex** en `@bubabeautystudio.com`. Cuando alguien responda a un email de marketing, llega a `info@` (o al alias que se configure).
- Los DKIM CNAMEs son los mismos; SPF y DMARC del apex cubren ambos servicios.
- Warning: el MAIL FROM `mail.bubabeautystudio.com` sigue apuntando al MX de SES feedback (`feedback-smtp.eu-west-1.amazonses.com`) — eso es solo para bounces de SES, no conflicta con WorkMail.

## Configuración en el iPhone (la dueña)

1. Ajustes → Mail → Cuentas → Añadir cuenta → Otra → Añadir cuenta de correo.
2. Nombre: `Buba Beauty Studio`.
3. Email: `info@bubabeautystudio.com`.
4. Contraseña: la que se asignó al primer login (no la temporal).
5. Descripción: `Buba oficial`.
6. Siguiente → IMAP.
7. Servidor de correo entrante:
   - Nombre del host: `imap.mail.eu-west-1.awsapps.com`
   - Usuario: `info@bubabeautystudio.com`
   - Contraseña: (la del step 4)
8. Servidor de correo saliente (SMTP):
   - Nombre del host: `smtp.mail.eu-west-1.awsapps.com`
   - Usuario y contraseña: iguales.
9. Siguiente → se validan conexiones → guardar.

Alternativa: Outlook para iOS admite WorkMail nativo (Exchange-compat) — login con el email + password, detección automática via autodiscover CNAME.

## Borrado seguro (si se quiere cancelar)

```bash
# 1. Deregister todos los usuarios
aws workmail list-users --organization-id $ORG --region $REGION --query 'Users[?State==`ENABLED`].Id' --output text | xargs -I{} aws workmail deregister-from-work-mail --organization-id $ORG --entity-id {} --region $REGION

# 2. Delete organization (pasa a Deleted State; 30 días de grace period para rollback via AWS Support)
aws workmail delete-organization --organization-id $ORG --delete-directory --region $REGION

# 3. Borrar registros DNS específicos de WorkMail vía terraform apply tras quitarlos de dns.tf
```
