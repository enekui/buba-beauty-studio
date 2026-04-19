# Buba Beauty Studio — App iOS (Capacitor)

App nativa de iPhone que empaqueta la experiencia web de
[bubabeautystudio.com](https://bubabeautystudio.com) como aplicación
publicable en App Store. Usa [Capacitor 6](https://capacitorjs.com)
como shell nativo: el HTML, CSS y JS de la web son la **misma fuente
de verdad** (se sincronizan a `www/` con `sync-web.sh`), y sobre esa
base se añaden integraciones nativas iOS:

- **Reservar** → abre Booksy en `SFSafariViewController` embebido.
- **Llamar / WhatsApp / Apple Maps** → barra flotante visible solo en la app.
- **Notificaciones push** (promociones) → OneSignal + APNs.

El código de la web vive en la raíz del repo (`index.html`, `img/`, `js/`).
Este directorio `ios-app/` contiene solo lo específico del shell iOS.

## Requisitos locales (una sola vez)

| Herramienta | Versión mínima | Cómo instalar |
|---|---|---|
| macOS | 13+ | — |
| Xcode | 15+ | App Store |
| Node.js | 20+ | `brew install node` |
| CocoaPods | 1.13+ | `brew install cocoapods` o `sudo gem install cocoapods` |
| Apple Developer Program | activo | [developer.apple.com](https://developer.apple.com) (99€/año) |

## Bootstrap inicial

La primera vez en un Mac nuevo:

```bash
cd ios-app
npm install                                 # dependencias Capacitor + plugins
npm run build:web                           # copia ../index.html + ../img/ + ../js/ → www/
npx cap add ios                             # genera proyecto Xcode en ios/
npx cap sync ios                            # sincroniza www/ y plugins dentro del bundle
npm run assets:generate                     # genera íconos y splash (necesita resources/icon.png y resources/splash.png)
npx cap open ios                            # abre Xcode
```

En Xcode:

1. Seleccionar el target `App`.
2. *Signing & Capabilities* → Team = «Buba Beauty Studio» (cuenta Apple Developer).
3. Añadir capabilities: **Push Notifications** y **Background Modes → Remote notifications**.
4. `Product → Run` (▶) con un simulador iPhone 15 Pro.

## Día a día

Cada vez que la web (`../index.html`, `../img/`, `../js/`) cambia y queremos reflejarlo en la app:

```bash
cd ios-app
npm run ios:sync        # = build:web + cap sync ios
npm run ios:run         # build:web + cap sync + abrir en simulador
```

Scripts disponibles:

| Script | Qué hace |
|---|---|
| `npm run build:web` | Ejecuta `scripts/sync-web.sh`, copia la web al bundle `www/` |
| `npm run ios:sync` | `build:web` + `cap sync ios` |
| `npm run ios:open` | Abre el proyecto en Xcode |
| `npm run ios:run` | Compila y lanza en el simulador iOS |
| `npm run assets:generate` | Genera íconos y launch screen desde `resources/` |

## Push notifications (OneSignal)

El código puente vive en `../js/push.js` y solo se activa si
`window.Capacitor.isNativePlatform()` es `true`, por lo que no afecta
a la web pública.

Para habilitar push en una build:

1. Crear app en [OneSignal](https://dashboard.onesignal.com) → obtener **App ID**.
2. Reemplazar el placeholder `ONESIGNAL_APP_ID` en `../js/push.js`.
3. En Apple Developer portal:
   - Crear una **APNs Auth Key (.p8)**.
   - Subir la `.p8` a OneSignal → *Settings → Platforms → Apple iOS*.
4. En Xcode, activar las capabilities **Push Notifications** y **Background Modes → Remote notifications**.
5. Probar con un dispositivo físico (los push no funcionan en simulador salvo notificaciones locales).

Para lanzar una promoción manualmente: dashboard de OneSignal →
*Messages → New Push*.

## App Store Connect — submission checklist

- [ ] Bundle ID `com.bubabeautystudio.app` creado en *Identifiers* del portal Apple.
- [ ] App Store Connect → *My Apps → New App*.
- [ ] Categorías: primaria **Lifestyle**, secundaria **Health & Fitness**.
- [ ] Age rating: **4+**.
- [ ] Privacy policy URL: `https://bubabeautystudio.com/privacy.html` (ya publicada en la web).
- [ ] Screenshots iPhone 6.7" (1290×2796) y 6.5" (1242×2688), mínimo 3 cada uno.
- [ ] App Privacy → declarar **Device ID (token APNs)** para notificaciones, sin linking a identidad.
- [ ] *App Review Information* → notas al revisor explicando las features nativas (Booksy embebido, llamar, WhatsApp, Apple Maps, push) para evitar rechazo §4.2.
- [ ] Archive en Xcode → Distribute App → App Store Connect → TestFlight.
- [ ] Tras pruebas TestFlight → Submit for Review.

## Estructura generada

```
ios-app/
├── capacitor.config.ts    Config del shell (appId, webDir, plugins, whitelist)
├── package.json           Dependencias Capacitor + plugins
├── scripts/sync-web.sh    Copia la web → www/
├── resources/             (no commitear los generados) icon.png 1024², splash.png 2732²
├── www/                   ← GENERADO, no commitear; sync-web.sh lo reconstruye
└── ios/                   ← GENERADO por `cap add ios`; Xcode project
```

## Troubleshooting

**`pod install` falla con «CocoaPods not installed»**
→ `brew install cocoapods` o `sudo gem install cocoapods`.

**La app carga en blanco en el simulador**
→ Probablemente `www/` está vacío o desactualizado. Ejecutar `npm run build:web` y luego `npx cap sync ios`.

**Apple rechaza la build con §4.2 (Minimum Functionality)**
→ Asegurarse de que la barra flotante (`#native-quick-actions`) es visible en las screenshots y que el revisor puede probar llamada, WhatsApp y Apple Maps. Añadir notas explicativas en *App Review Information*.

**Las notificaciones push no llegan al iPhone físico**
→ Verificar (1) que la `.p8` está subida a OneSignal, (2) que el Bundle ID en OneSignal coincide con el de Xcode, (3) que las capabilities Push Notifications y Background Modes están activas, (4) que el usuario aceptó el diálogo de permisos.
