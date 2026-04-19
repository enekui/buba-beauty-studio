(function () {
  'use strict';

  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  function resolveApiBase() {
    if (typeof window !== 'undefined' && typeof window.BUBA_API_BASE === 'string' && window.BUBA_API_BASE) {
      return window.BUBA_API_BASE.replace(/\/+$/, '');
    }
    const meta = document.querySelector('meta[name="buba-api-base"]');
    if (meta && meta.content) {
      return meta.content.replace(/\/+$/, '');
    }
    return null;
  }

  function setStatus(el, message, kind) {
    if (!el) return;
    el.textContent = message || '';
    el.classList.remove('is-success', 'is-error');
    if (kind) el.classList.add('is-' + kind);
  }

  function onReady() {
    const form = document.querySelector('form.subscribe-form');
    if (!form) return;

    const statusEl = form.querySelector('.subscribe-status');
    const button = form.querySelector('button[type="submit"]');
    const emailInput = form.querySelector('input[type="email"]');
    const consentInput = form.querySelector('input[name="consent"]');

    form.addEventListener('submit', async function (event) {
      event.preventDefault();

      const email = (emailInput && emailInput.value || '').trim();
      const consent = !!(consentInput && consentInput.checked);

      if (!EMAIL_RE.test(email)) {
        setStatus(statusEl, 'Introduce un email válido.', 'error');
        if (emailInput) emailInput.focus();
        return;
      }

      if (!consent) {
        setStatus(statusEl, 'Debes aceptar la política de privacidad.', 'error');
        return;
      }

      const apiBase = resolveApiBase();
      if (!apiBase || apiBase.indexOf('__API_BASE__') !== -1) {
        setStatus(statusEl, 'El servicio no está disponible ahora mismo. Inténtalo más tarde.', 'error');
        return;
      }

      if (button) button.disabled = true;
      setStatus(statusEl, 'Enviando…', null);

      try {
        const response = await fetch(apiBase + '/subscribe', {
          method: 'POST',
          mode: 'cors',
          headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
          body: JSON.stringify({ email: email, consent: consent, source: 'web-footer', locale: 'es' })
        });

        if (!response.ok) {
          throw new Error('HTTP ' + response.status);
        }

        form.reset();
        setStatus(statusEl, 'Revisa tu bandeja para confirmar la suscripción.', 'success');
      } catch (err) {
        setStatus(statusEl, 'No hemos podido procesar tu suscripción. Inténtalo de nuevo en unos minutos.', 'error');
      } finally {
        if (button) button.disabled = false;
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onReady);
  } else {
    onReady();
  }
})();
