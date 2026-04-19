# Buba Beauty Studio — Plataforma Digital

## What This Is

Plataforma digital completa de un salón de belleza en A Coruña: landing web pública (`bubabeautystudio.com`), app iOS nativa en App Store, sistema de email marketing propio y panel admin para lanzar campañas. Todo desplegado sobre AWS del propio negocio, sin dependencias de terceros de marketing (Mailchimp/Brevo/etc).

## Core Value

App iOS en TestFlight corriendo en el iPhone de la dueña con la experiencia idéntica a la web, botones nativos (llamar, WhatsApp, mapa) y push notifications de promociones funcionando end-to-end.

## Requirements

### Validated

<!-- Shipped y en producción tras los PR #1 y #2. -->

- ✓ Landing web pública con SEO completo, galería, reseñas Booksy, CTA reservas — v0 en `main`
- ✓ App iOS skeleton Capacitor + native-bridge + barra flotante Llamar/WhatsApp/Maps + push.js stub — PR #1
- ✓ Stack AWS email marketing desplegado en producción (eu-west-1): 98 recursos Terraform, 6 Lambdas, API Gateway HTTP + Cognito JWT, SES v2 con DKIM verificado, 3 plantillas subidas, admin web en `admin.bubabeautystudio.com` — PR #2
- ✓ Formulario de suscripción en footer de `index.html` apuntando a la API real — commit 87c8af9
- ✓ `privacy.html` con sección 8 Marketing (RGPD-compliant) — PR #2

### Active

<!-- Hipótesis hasta que cierre el milestone v1.0 "TestFlight + primera campaña". -->

**Track AWS email (autónomo hasta donde AWS Support permita)**

- [ ] Request exit sandbox SES enviado y aprobado por AWS (24-48h review)
- [ ] Primera clienta real registrada via form público de `bubabeautystudio.com`
- [ ] Primera campaña `monthly_promo` enviada a `promociones` (>10 suscriptoras opt-in)
- [ ] Web pública redesplegada con el `index.html` mergeado (hosting por determinar)
- [ ] DMARC endurecido: `p=none` → `p=quarantine` tras 2 semanas limpias
- [ ] Backend Terraform remoto (S3+DynamoDB lock) configurado

**Track iOS (bloqueado por hardware local y cuenta Apple)**

- [ ] `brew install cocoapods` + `brew install imagemagick` en el Mac del usuario
- [ ] `cd ios-app && npm install && npx cap add ios && npx cap sync ios` (genera proyecto Xcode)
- [ ] Icono 1024² + splash 2732² generados desde `img/logo-buba.jpg` con paleta cream
- [ ] Apple Developer Program activo (99 €/año) y bundle `com.bubabeautystudio.app` registrado
- [ ] Cuenta OneSignal creada, App ID pegado en `js/push.js`, APNs `.p8` subida
- [ ] Build firmada en TestFlight instalable en iPhone físico de la dueña
- [ ] Screenshots 6.7" + 6.5" + descripción + keywords preparados para App Store Connect
- [ ] Build aprobada por Apple Review y pública en App Store

### Out of Scope

<!-- Boundaries explícitas para evitar scope creep. -->

- Backoffice para la dueña con métricas del salón (agenda, ingresos, stock) — el admin web de email marketing es el único panel en v1; métricas del negocio las sigue dando Booksy.
- Android app — Capacitor lo soportaría con `cap add android` pero cada tienda suma tiempo de QA y review. Diferido hasta que haya tracción iOS medida en instalaciones reales.
- Analytics avanzado tipo QuickSight/Pinpoint — los eventos SES ya llegan a CloudWatch; dashboards enriquecidos son mejora futura.
- Sistema de reservas propio — seguimos delegando en Booksy indefinidamente (API de Booksy es consumer-facing, no hay motivo para competir con ellos).
- Importación masiva de contactos desde CSV Booksy — RGPD requiere consentimiento expreso del marketing que Booksy no captura al reservar; la lista crece orgánicamente desde el form público.
- Internacionalización (EN/GL) — el público del salón es local hispanohablante; deferred.

## Context

**Estado del repo al arrancar GSD (2026-04-19):**

- `main` contiene los PR #1 (iOS) y #2 (AWS email) ya mergeados.
- Infra AWS viva en cuenta `372370374261` eu-west-1; dominio verificado, admin panel servido por CloudFront.
- No existe `ios-app/ios/` (proyecto Xcode) en el repo porque requiere CocoaPods local para generarse.
- No hay iconos iOS en `ios-app/resources/` por falta de ImageMagick en la máquina de trabajo actual.

**Documentos previos:**

- `/Users/adianny/.claude/plans/vamos-a-planificar-el-squishy-hedgehog.md` — plan inicial iOS Capacitor (5 fases).
- `/Users/adianny/.claude/plans/aws-email-marketing-buba.md` — plan inicial AWS email marketing (5 fases).

**Bloqueos externos conocidos:**

- **AWS SES sandbox**: requiere ticket manual a AWS Support vía consola; sin API. Review humano 24-48h.
- **Apple Developer Program**: 99 €/año, pago con tarjeta y verificación SMS por la dueña.
- **CocoaPods + ImageMagick**: `brew install` requiere password sudo en el Mac local.
- **Hosting actual de `bubabeautystudio.com`**: desconocido, pendiente de identificar (probablemente GitHub Pages, Netlify o similar).

**Cuenta operadora:**

- AWS: IAM user `adianny` del account 372370374261.
- Cognito admin: `adianny@me.com` (invitación en su bandeja tras el primer apply).
- GitHub: `enekui/buba-beauty-studio`.

## Constraints

- **Coste**: infra AWS < 5 USD/mes. Budget alert configurado a ese umbral; fase que lo supere debe revisarse.
- **Dependencias externas**: cero nuevas. Stack cerrado en Capacitor + AWS SES + Cognito + CloudFront + OneSignal. No añadir Mailchimp, Sentry, Firebase, etc.
- **RGPD estricto**: doble opt-in obligatorio, `privacy.html` siempre al día, no importar contactos sin consent expreso documentado.
- **Workflow Git**: PRs siempre (nunca merge directo a main), worktrees para sesiones concurrentes. Los commits NO tienen que ser pequeños en este repo — se permite 1 commit grande por PR/fase para avanzar rápido.
- **Autonomía GSD**: todo lo que Claude pueda hacer vía CLI/API lo hace; solo para en los puntos que genuinamente requieren humano (Apple Dev signup, SES sandbox ticket, sudo brew, login Cognito inicial, pago tarjeta).

## Key Decisions

<!-- Decisiones que constrainan trabajo futuro. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Capacitor (no WKWebView nativo ni React Native) | Reutiliza `index.html` sin reescribir; aporta hooks nativos suficientes para §4.2 Apple Review; puerta abierta a Android | ✓ Good |
| SES Contact Lists (no DynamoDB custom para contactos) | Nativo, unsubscribe link gestionado por AWS (RFC 8058), suppression automática | ✓ Good |
| Cognito PKCE (no API key estática para admin) | Multi-admin sin cambios de código, MFA opcional, free tier cubre 50 MAU | ✓ Good |
| HTTP API Gateway (no REST) | 70% más barato, latencia menor, soporta JWT authorizer nativo | ✓ Good |
| Lambda arm64 (Graviton) | 20% más barato por invocación que x86 a igual perf | ✓ Good |
| OneSignal (no APNs directo ni Firebase) | UI web para enviar push sin backend propio; plan free cubre el volumen esperado | — Pending |
| Terraform state local inicialmente | El primer apply se hizo desde el Mac del usuario; migrar a S3 remote backend cuando haya múltiples operadores | ⚠️ Revisit |
| No Android en v1 | Enfoque + QA simple; Capacitor lo permite más adelante sin refactor | — Pending |

---
*Last updated: 2026-04-19 after initialization*
