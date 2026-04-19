/*
 * push.js
 *
 * Inicializacion de notificaciones push via OneSignal.
 * Solo se ejecuta dentro de la app nativa (Capacitor); en navegador es no-op.
 *
 * Antes de usar en produccion:
 *   1. Crear app en https://dashboard.onesignal.com -> App ID.
 *   2. Reemplazar ONESIGNAL_APP_ID abajo con el App ID real.
 *   3. Subir la APNs Auth Key (.p8) en OneSignal -> Settings -> Platforms -> Apple iOS.
 *   4. En Xcode, activar capabilities: Push Notifications + Background Modes > Remote notifications.
 *
 * Segmentacion basica: etiqueta al usuario con la seccion mas visitada
 * (nails / lashes / skincare) para enviar promociones relevantes.
 */

(function () {
  'use strict';

  var ONESIGNAL_APP_ID = 'REPLACE_WITH_ONESIGNAL_APP_ID';

  var isNative = !!(window.Capacitor && typeof window.Capacitor.isNativePlatform === 'function' && window.Capacitor.isNativePlatform());
  if (!isNative) return;

  function whenOneSignalReady() {
    return new Promise(function (resolve) {
      var tries = 0;
      (function check() {
        if (window.plugins && window.plugins.OneSignal) return resolve(window.plugins.OneSignal);
        if (tries++ > 40) return resolve(null); // ~4s timeout
        setTimeout(check, 100);
      })();
    });
  }

  async function initPush() {
    if (!ONESIGNAL_APP_ID || ONESIGNAL_APP_ID === 'REPLACE_WITH_ONESIGNAL_APP_ID') {
      // Sin App ID configurado no arrancamos OneSignal; deja la app sin push pero funcional.
      return;
    }
    var OneSignal = await whenOneSignalReady();
    if (!OneSignal) return;

    try {
      OneSignal.setAppId(ONESIGNAL_APP_ID);
    } catch (err) {
      // API nueva (v5+): Sin setAppId, se configura via Initialize en Swift. Ignorar en ese caso.
    }

    if (typeof OneSignal.promptForPushNotificationsWithUserResponse === 'function') {
      OneSignal.promptForPushNotificationsWithUserResponse(function () {});
    }

    trackSectionInterest(OneSignal);
  }

  function trackSectionInterest(OneSignal) {
    var sectionToTag = {
      'servicios': 'nails',
      'galeria':   'lashes',
      'opiniones': 'skincare',
    };
    var sent = {};
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var id = entry.target.id;
        var tag = sectionToTag[id];
        if (!tag || sent[tag]) return;
        sent[tag] = true;
        try { OneSignal.sendTag('service_interest_' + tag, '1'); } catch (_) {}
      });
    }, { threshold: 0.4 });

    Object.keys(sectionToTag).forEach(function (id) {
      var el = document.getElementById(id);
      if (el) observer.observe(el);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initPush);
  } else {
    initPush();
  }
})();
