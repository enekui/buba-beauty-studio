/*
 * native-bridge.js
 *
 * Puente entre la web publica (bubabeautystudio.com) y el shell nativo
 * Capacitor/iOS. En navegador normal es no-op: `window.Capacitor` no existe
 * y la pagina se comporta igual que siempre. Dentro de la app:
 *
 *   - Los enlaces a Booksy / Instagram abren en SFSafariViewController
 *     embebido (plugin @capacitor/browser) en vez de salir a Safari.
 *   - Se muestra una barra flotante de accesos rapidos (Llamar, WhatsApp,
 *     Apple Maps) que enriquece la experiencia y evita el rechazo de
 *     Apple por "solo wrapper web".
 *
 * Requisitos en index.html:
 *   - Cargar este archivo con <script defer src="js/native-bridge.js"></script>
 *   - Tener un contenedor <div id="native-quick-actions" hidden>...</div>
 *     con los tres enlaces: .nqa-call, .nqa-whatsapp, .nqa-maps
 */

(function () {
  'use strict';

  var PHONE = '+34604028359';
  var WHATSAPP_URL = 'https://wa.me/34604028359?text=' + encodeURIComponent('Hola Buba, me gustaria pedir informacion.');
  var MAPS_NATIVE = 'maps://?daddr=' + encodeURIComponent('Rua Curtis 8, 15009 A Coruna');
  var MAPS_FALLBACK = 'https://maps.apple.com/?daddr=' + encodeURIComponent('Rua Curtis 8, 15009 A Coruna');

  var isNative = !!(window.Capacitor && typeof window.Capacitor.isNativePlatform === 'function' && window.Capacitor.isNativePlatform());

  function openExternal(url) {
    // _system abre en el navegador externo o en la app registrada para el scheme (tel:, maps:, whatsapp://)
    window.open(url, '_system');
  }

  async function openInAppBrowser(url) {
    try {
      var Browser = window.Capacitor.Plugins.Browser;
      await Browser.open({ url: url, presentationStyle: 'popover' });
    } catch (err) {
      openExternal(url);
    }
  }

  function shouldInterceptAsInAppBrowser(url) {
    return /(^https?:\/\/)(.*\.)?(booksy\.com|instagram\.com)(\/|$)/i.test(url);
  }

  function interceptLinkClicks() {
    document.addEventListener('click', function (e) {
      var anchor = e.target && e.target.closest ? e.target.closest('a[href]') : null;
      if (!anchor) return;
      var url = anchor.href;
      if (!url) return;
      if (shouldInterceptAsInAppBrowser(url)) {
        e.preventDefault();
        openInAppBrowser(url);
      }
    });
  }

  function mountQuickActions() {
    var container = document.getElementById('native-quick-actions');
    if (!container) return;
    container.hidden = false;
    container.classList.add('is-native');

    var callBtn = container.querySelector('.nqa-call');
    var waBtn   = container.querySelector('.nqa-whatsapp');
    var mapBtn  = container.querySelector('.nqa-maps');

    if (callBtn)  callBtn.addEventListener('click', function (e) { e.preventDefault(); openExternal('tel:' + PHONE); });
    if (waBtn)    waBtn.addEventListener('click',   function (e) { e.preventDefault(); openExternal(WHATSAPP_URL); });
    if (mapBtn)   mapBtn.addEventListener('click',  function (e) {
      e.preventDefault();
      openExternal(MAPS_NATIVE);
      // Fallback: si el scheme maps:// no esta soportado, el WebView muestra una pagina en blanco.
      // El plugin @capacitor/app emite appUrlOpen que podriamos usar; para el MVP confiamos en que
      // iOS siempre tiene Apple Maps. Si se detectase fallo en QA, cambiar a MAPS_FALLBACK.
      void MAPS_FALLBACK;
    });
  }

  function configureStatusBar() {
    try {
      var StatusBar = window.Capacitor.Plugins.StatusBar;
      if (!StatusBar) return;
      StatusBar.setStyle({ style: 'DARK' }).catch(function () {});
      StatusBar.setBackgroundColor({ color: '#FAF7F4' }).catch(function () {});
    } catch (_) {}
  }

  function hideSplash() {
    try {
      var SplashScreen = window.Capacitor.Plugins.SplashScreen;
      if (!SplashScreen) return;
      SplashScreen.hide({ fadeOutDuration: 400 }).catch(function () {});
    } catch (_) {}
  }

  function init() {
    if (!isNative) return;
    document.documentElement.classList.add('is-native-ios');
    interceptLinkClicks();
    mountQuickActions();
    configureStatusBar();
    hideSplash();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
