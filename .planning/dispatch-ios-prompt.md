# Prompt para Claude Dispatch — iOS final mile

Prompt autoportante para una sesión Claude Code separada (dispatch, subagente, o ventana nueva) que complete la última parte manual del track iOS sin contexto previo de la conversación actual. Está redactado para que pueda ejecutarse tal cual contra un agente general-purpose con acceso Bash.

---

## Prompt

```
Estás en el Mac del usuario (Darwin arm64, Apple Silicon). Repo: /Users/adianny/git/buba-beauty-studio. Rama: main. Xcode 26.4.1 YA instalado en /Applications/Xcode.app. Tu misión: completar el último tramo del iOS bootstrap hasta dejar la app corriendo en el iPhone físico del usuario.

ESTADO ACTUAL (no re-ejecutar, ya hecho):
- Proyecto Xcode en ios-app/ios/App/App.xcworkspace con 9 pods, iconos + splash en Assets.xcassets, Info.plist con NSUserNotificationUsageDescription + UIBackgroundModes=[remote-notification] + CFBundleDisplayName="Buba Beauty".
- project.pbxproj pre-patchado con DEVELOPMENT_TEAM=S8D97RR3SX + CODE_SIGN_ENTITLEMENTS=App/App.entitlements en ambos build configs (Debug, Release).
- App/App.entitlements con <key>aps-environment</key><string>development</string>.
- Bundle ID com.bubabeautystudio.app YA registrado en Apple Developer Portal (Team S8D97RR3SX) con capability Push Notifications.
- APNs Auth Key ID JS999HP9JQ, archivo .p8 guardado por el usuario (NO está en el repo ni necesitas acceder al archivo).
- Apple Developer Program activo en la cuenta del usuario.
- OneSignal App ID: placeholder "REPLACE_WITH_ONESIGNAL_APP_ID" sigue en js/push.js — se sustituye cuando el usuario complete el signup (fuera del scope de este prompt).
- Credenciales Apple + WorkMail en ~/.claude/secrets/ (chmod 600, no tocar a menos que necesites leer el Team ID).

TAREAS A EJECUTAR (en orden):

1. Verifica que Xcode está instalado: `ls -d /Applications/Xcode.app && /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -version`. Debe devolver Xcode 26.x.

2. Apuntar CLI tools al Xcode full (requiere sudo — el sistema pedirá password al usuario):
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   Si el sudo falla o el usuario cancela el prompt, PARA y reporta. No intentes continuar sin Xcode activo.

3. Verificar que xcodebuild ya funciona sin el error de Command Line Tools:
   xcodebuild -version

4. Abrir Xcode una sola vez para que el usuario meta su Apple ID (NO se puede automatizar — es UI obligatoria):
   open -a Xcode
   Mostrar al usuario estas instrucciones EXACTAS:
   "Xcode se acaba de abrir. Haz lo siguiente y avísame cuando termines:
     a) Xcode → Settings (⌘,) → Accounts → '+' → Apple ID → login con TU cuenta (la que tiene Apple Developer Program activo).
     b) Verás tu equipo 'Adianny Ramírez Armenteros' en la lista con un check. NO necesitas tocar nada más.
     c) Opcional: puedes cerrar Xcode con ⌘Q o dejarlo abierto."
   ESPERA confirmación del usuario (via user input "login ok" o similar). NO continúes sin esa confirmación porque la firma fallará.

5. Smoke test del build (sin firmar, solo compila):
   cd /Users/adianny/git/buba-beauty-studio/ios-app/ios
   xcodebuild -workspace App/App.xcworkspace -scheme App \
     -configuration Debug \
     -destination 'generic/platform=iOS Simulator' \
     -derivedDataPath /tmp/buba-ios-derived \
     clean build 2>&1 | tail -25

   Resultado esperado: "** BUILD SUCCEEDED **".
   Si falla con errores de signing: el usuario no ha completado el paso 4. Pídele que lo haga y reintenta.
   Si falla con errores de código Swift/Pod: reporta el error textual y para — no intentes "arreglar" el código.

6. Detectar iPhone conectado:
   xcrun devicectl list devices 2>&1 | head -10
   O alternativamente:
   system_profiler SPUSBDataType 2>/dev/null | grep -iE "iphone|ipad" | head -5

   Si NO hay iPhone detectado: mostrar al usuario "Conecta tu iPhone con cable USB-C/Lightning al Mac. Desbloquéalo y pulsa 'Confiar' cuando el iPhone pregunte. Luego avísame."
   ESPERA confirmación.

7. Con iPhone conectado, instalar + lanzar la app en el device:
   - Captura UDID del iPhone: xcrun devicectl list devices --json-output /tmp/devices.json && cat /tmp/devices.json | python3 -c "import json,sys; [print(d['hardwareProperties']['udid']) for d in json.load(sys.stdin)['result']['devices'] if d['connectionProperties']['transportType']=='wired']"
   - Build firmado para device:
     xcodebuild -workspace App/App.xcworkspace -scheme App \
       -configuration Debug \
       -destination "id=<UDID_CAPTURADO>" \
       -derivedDataPath /tmp/buba-ios-device \
       build
   - Install + lanzar en iPhone:
     xcrun devicectl device install app --device <UDID> /tmp/buba-ios-device/Build/Products/Debug-iphoneos/App.app
     xcrun devicectl device process launch --device <UDID> com.bubabeautystudio.app

   Si el install falla con "Could not verify developer": el usuario tiene que ir en el iPhone a Ajustes → General → VPN y gestión de dispositivos → Apple ID del usuario → Confiar. Explícaselo y reintenta.

8. Verificar visualmente que la app abrió:
   xcrun devicectl device info --device <UDID> 2>&1 | head -5
   (No hay forma de screenshot del device via CLI sin Xcode UI, pero el usuario puede confirmar visualmente).

9. Reportar al usuario:
   - BUILD SUCCEEDED / FAILED del smoke test.
   - iPhone detectado: sí/no + UDID.
   - App instalada + lanzada: sí/no.
   - Qué falta para push notifications funcionales (OneSignal signup + App ID — explícitamente fuera de tu scope, solo recuerda al usuario).
   - Cualquier error textual íntegro.

LO QUE NO DEBES HACER:
- NO usar sudo sin explicar al usuario por qué (Xcode install tools lo requieren). NO metas credenciales ni passwords por ti mismo.
- NO crees cuenta OneSignal, ni entres a developer.apple.com, ni toques App Store Connect.
- NO modifiques código Swift ni archivos .xcodeproj (ya están configurados). Si algo está mal, repórtalo, no lo "arregles" especulativamente.
- NO commitees nada a Git. El commit de cualquier cambio (ej. si editas project.pbxproj por alguna razón) lo hará el usuario o la siguiente sesión.
- NO intentes instalar OTRO Xcode ni command line tools — ya están.
- NO uses Docker (el usuario acaba de limpiar 87 GB de Docker VM vieja).

REPORTA TODO ERROR LITERALMENTE. Si algo no es obvio, para y pregunta.
```

---

## Uso

Copia el bloque entre las dos líneas `---` y pégalo como primer mensaje en una sesión nueva de Claude Code en este Mac (`claude` en un terminal en el directorio del repo, o dispatch programado).

El agente necesitará permisos para:
- `Bash` (para `sudo`, `xcodebuild`, `xcrun`, `system_profiler`)
- `Read/Edit` por si hay que ajustar configs
- Capacidad de esperar input interactivo del usuario (sudo password, confirmación tras login Xcode, confirmación iPhone conectado).

## Qué se hace fuera de este prompt

- **OneSignal signup** — solo el usuario puede crear cuenta en onesignal.com. Una vez tenga el App ID (UUID), una sesión posterior (o el usuario directamente) sustituye el placeholder `REPLACE_WITH_ONESIGNAL_APP_ID` en `js/push.js` por el valor real, corre `cd ios-app && npm run build:web && npx cap sync ios`, commit + push, y reinstala la app con `xcrun devicectl device install app`.
- **TestFlight + App Store submission** — fases 4-01 y 4-02 del ROADMAP (`.planning/phases/04-ios-testflight-appstore/`). Requieren screenshots desde Simulator, metadata en App Store Connect, Submit for Review manual.
