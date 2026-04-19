# Roadmap: Buba Beauty Studio — Plataforma Digital

## Overview

Plataforma digital completa del salón: web pública + app iOS en App Store + email marketing AWS-native con admin propio. Los PR #1 (iOS Capacitor skeleton) y #2 (AWS email stack) ya están mergeados y en producción. Este roadmap cubre el último tramo: endurecer AWS email para clientas reales, desplegar la web pública con el form funcional, arrancar el build iOS en local, y subir la app a TestFlight y App Store. La estructura prioriza tracks paralelos cuando los bloqueos externos (Apple Developer, SES sandbox, sudo brew) permiten avanzar otro frente mientras se espera.

## Domain Expertise

None (sin skills/expertise/ disponibles en el entorno; apoyarse en los dos planes previos de `~/.claude/plans/` cuando sea útil).

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: AWS email hardening para clientas reales** — Ticket exit sandbox SES + Terraform state remoto + DMARC progression + warm-up plan
- [ ] **Phase 2: Deploy web pública con form funcional** — Identificar hosting, subir index.html + privacy.html + js/subscribe.js + js/native-bridge.js + js/push.js, verificar end-to-end la primera suscripción real
- [ ] **Phase 3: iOS local bootstrap + firma** — brew install, cap add ios, generar iconos, Apple Developer Program + bundle + OneSignal, build firmada local
- [ ] **Phase 4: TestFlight + App Store submission** — Archive upload, screenshots, metadata, review submission, iterar sobre feedback Apple hasta public release

## Phase Details

### Phase 1: AWS email hardening para clientas reales

**Goal**: Dejar el stack AWS email en estado "production-ready" para que la primera campaña real a clientas no se bloquee por nada controlable por Claude. El ticket de exit sandbox SES debe estar enviado (lo único que no puedo disparar sin aprobar en consola humana); el resto son cambios de infra autónomos.

**Depends on**: Nothing — PR #2 ya mergeado, infra viva.
**Research**: Unlikely (SES sandbox form copy, DMARC progression y Terraform S3 backend son patrones cerrados).
**Plans**: 2 plans

Plans:
- [ ] 01-01: **Backend Terraform remoto (S3 + DynamoDB lock)** — Crear bucket `buba-terraform-state-<account>` y tabla `buba-terraform-locks`; migrar el state actual con `terraform init -migrate-state`; actualizar `aws-email/main.tf` para descomentar el bloque backend.
- [ ] 01-02: **SES production request + DMARC quarantine plan** — Rellenar y enviar el formulario de salida del sandbox SES vía consola (única parte humana); añadir Terraform var toggle para subir a `p=quarantine` a los 14 días limpios; documentar el warm-up (primeros 14 días < 500 envíos/día).

### Phase 2: Deploy web pública con form funcional

**Goal**: El form del footer de `bubabeautystudio.com` crea contactos reales en la SES Contact List. Requiere saber dónde se sirve el dominio hoy, subir los archivos actualizados de `main` y verificar con una suscripción propia end-to-end.

**Depends on**: Phase 1 (warm-up / sandbox en marcha — aunque sandbox no bloquea la suscripción, sí bloquea que a clientas les llegue el email de confirmación).
**Research**: Likely (no sabemos qué hosting sirve hoy `bubabeautystudio.com`; hay que investigar DNS, NS, TLS cert para deducirlo).
**Research topics**:
- `dig bubabeautystudio.com +noall +answer` + `curl -sI https://bubabeautystudio.com | grep -i server` para identificar el provider.
- Si es GitHub Pages → CNAME en /docs; si Netlify/Vercel → dashboard propio; si S3+CloudFront en la misma cuenta → deploy directo.
**Plans**: 2 plans

Plans:
- [ ] 02-01: **Identificar hosting y pipeline de deploy** — Investigar cómo se sirve hoy la web, documentar en `.planning/notes/web-hosting.md`, proponer script `deploy-web.sh` si aplica. Si es hosting propio AWS, crear el target Terraform en un nuevo `aws-web/` o extender `aws-email/`.
- [ ] 02-02: **Desplegar y verificar end-to-end** — Subir `index.html` + `privacy.html` + `js/*.js` al hosting identificado. Suscripción con email propio: (a) POST 200 a `/subscribe`, (b) email de doble opt-in recibido, (c) click en link → contacto OPT_IN en SES, (d) aparece en la UI de SES Contact List.

### Phase 3: iOS local bootstrap + firma

**Goal**: Tener una build `.ipa` firmada del app iOS en local, instalable vía Xcode en un iPhone físico. Cubre bootstrap del proyecto Capacitor + cuenta Apple Developer + OneSignal + assets.

**Depends on**: Nothing técnico (puede empezar en paralelo a Phase 1). Requiere acceso físico al Mac del usuario para `brew install` y login Xcode.
**Research**: Likely (OneSignal Capacitor plugin setup, APNs .p8 creation flow en Apple Dev portal actual 2026, @capacitor/assets generation con backgrounds).
**Research topics**:
- OneSignal Capacitor plugin: `onesignal-cordova-plugin` vs `@onesignal/onesignal-capacitor-plugin` (qué está vigente en 2026).
- Apple Developer: pasos exactos del create APNs Key .p8 + bundle registration + provisioning profile automático vs manual para primera TestFlight.
- `@capacitor/assets generate`: cómo especificar padding/background para que el icono cuadrado no se recorte en iOS (splash tiene safe zones distintas).
**Plans**: 3 plans

Plans:
- [ ] 03-01: **Bootstrap local Capacitor + generar iconos** — `brew install cocoapods imagemagick`, `npm install && npx cap add ios && npx cap sync ios` en `ios-app/`. Generar icono 1024² desde `img/logo-buba.jpg` sobre fondo cream `#FAF7F4` con @capacitor/assets.
- [ ] 03-02: **Apple Developer + bundle + capabilities** — Pagar Apple Dev Program (99 €/año) si no está activo; registrar `com.bubabeautystudio.app`; en Xcode Signing & Capabilities asignar team + activar Push Notifications + Background Modes > Remote notifications.
- [ ] 03-03: **OneSignal + APNs + primera build firmada** — Crear app OneSignal, pegar App ID en `js/push.js`, generar APNs Auth Key .p8, subir a OneSignal. `Product → Archive` en Xcode genera el .ipa firmado.

### Phase 4: TestFlight + App Store submission

**Goal**: App pública en App Store, descargable por cualquier usuaria. TestFlight como checkpoint intermedio antes de Submit for Review.

**Depends on**: Phase 3.
**Research**: Likely (altool/xcrun flags actuales para upload, App Store Connect API token si queremos automatizar, §4.2 Apple Review minimum functionality patterns para preparar las notes al reviewer).
**Research topics**:
- `xcrun altool --upload-app` vs `xcrun notarytool` vs Xcode Organizer "Distribute App".
- App Store Connect API: se puede usar token `.p8` + openapi spec para subir metadata vía CLI (evitar UI manual si es posible).
- Screenshots: formatos requeridos (1290×2796 iPhone 15 Pro Max, 1242×2688 iPhone 11 Pro Max).
- Notas al reviewer para §4.2 "Minimum Functionality" — explicar features nativas.
**Plans**: 2 plans

Plans:
- [ ] 04-01: **TestFlight internal** — Subir archive a App Store Connect (vía Xcode Organizer o `xcrun altool`). Añadir `adianny@me.com` + dueña del salón como testers internos. Verificar install en iPhone físico, smoke test de todas las features nativas + push.
- [ ] 04-02: **Submit for Review + launch** — Screenshots (Xcode Simulator `record`), descripción en español (adaptar `llms.txt`), keywords, categoría Lifestyle/Health & Fitness, age rating 4+, privacy policy URL `https://bubabeautystudio.com/privacy.html`, notas al reviewer explicando features nativas. Submit → iterar si hay rechazo → public release.

## Progress

**Execution Order:**
Phases execute in numeric order. 1 y 3 pueden arrancar en paralelo (sin dependencias cruzadas); 2 depende idealmente de 1 (warm-up empezado) y 4 depende de 3.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. AWS email hardening para clientas reales | 0/2 | Not started | - |
| 2. Deploy web pública con form funcional | 0/2 | Not started | - |
| 3. iOS local bootstrap + firma | 0/3 | Not started | - |
| 4. TestFlight + App Store submission | 0/2 | Not started | - |
