(function () {
  "use strict";

  const cfg = window.BUBA_ADMIN_CONFIG || {};
  const LS = sessionStorage;

  const els = {
    body: document.body,
    boot: document.getElementById("boot"),
    layout: document.getElementById("layout"),
    topbar: document.querySelector(".topbar"),
    userEmail: document.getElementById("user-email"),
    logoutBtn: document.getElementById("logout-btn"),
    form: document.getElementById("campaign-form"),
    subject: document.getElementById("subject"),
    bodyInput: document.getElementById("body"),
    topic: document.getElementById("topic"),
    testEmails: document.getElementById("test-emails"),
    sendTestBtn: document.getElementById("send-test-btn"),
    sendAllBtn: document.getElementById("send-all-btn"),
    previewFrame: document.getElementById("preview-frame"),
    historyTable: document.getElementById("history-table"),
    historyBody: document.getElementById("history-body"),
    historyEmpty: document.getElementById("history-empty"),
    dialog: document.getElementById("confirm-dialog"),
    confirmCount: document.getElementById("confirm-count"),
    toastStack: document.getElementById("toast-stack")
  };

  /* ----------------------- PKCE helpers ----------------------- */
  function b64url(buf) {
    const bytes = new Uint8Array(buf);
    let s = "";
    for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function randomVerifier(len) {
    const bytes = new Uint8Array(len || 48);
    crypto.getRandomValues(bytes);
    return b64url(bytes.buffer);
  }
  async function sha256(str) {
    const data = new TextEncoder().encode(str);
    return crypto.subtle.digest("SHA-256", data);
  }

  /* ----------------------- Auth state ------------------------- */
  function parseJwt(token) {
    try {
      const part = token.split(".")[1];
      const json = atob(part.replace(/-/g, "+").replace(/_/g, "/"));
      return JSON.parse(decodeURIComponent(
        Array.prototype.map.call(json, c => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2)).join("")
      ));
    } catch (_) { return null; }
  }

  function tokenIsFresh() {
    const tok = LS.getItem("id_token");
    if (!tok) return false;
    const claims = parseJwt(tok);
    if (!claims || !claims.exp) return false;
    return claims.exp * 1000 > Date.now() + 30000;
  }

  async function startLogin() {
    const verifier = randomVerifier(48);
    const challenge = b64url(await sha256(verifier));
    LS.setItem("pkce_verifier", verifier);
    const domain = (cfg.cognitoDomain || "").replace(/\/$/, "");
    const url = domain + "/login"
      + "?client_id=" + encodeURIComponent(cfg.cognitoClientId)
      + "&response_type=code"
      + "&scope=" + encodeURIComponent("openid email")
      + "&redirect_uri=" + encodeURIComponent(cfg.redirectUri)
      + "&code_challenge=" + challenge
      + "&code_challenge_method=S256";
    window.location.assign(url);
  }

  function logout() {
    LS.removeItem("id_token");
    LS.removeItem("access_token");
    LS.removeItem("refresh_token");
    LS.removeItem("id_token_expires_at");
    LS.removeItem("pkce_verifier");
    const domain = (cfg.cognitoDomain || "").replace(/\/$/, "");
    const base = (cfg.redirectUri || "").replace(/\/callback\.html$/, "/");
    const url = domain + "/logout"
      + "?client_id=" + encodeURIComponent(cfg.cognitoClientId)
      + "&logout_uri=" + encodeURIComponent(base);
    window.location.assign(url);
  }

  /* ----------------------- API ---------------------------------*/
  function apiUrl(path) {
    const base = (cfg.apiBase || "").replace(/\/$/, "");
    return base + path;
  }
  async function api(path, opts) {
    opts = opts || {};
    const headers = Object.assign({
      "Authorization": "Bearer " + LS.getItem("id_token"),
      "Accept": "application/json"
    }, opts.headers || {});
    if (opts.body && !headers["Content-Type"]) headers["Content-Type"] = "application/json";
    const res = await fetch(apiUrl(path), {
      method: opts.method || "GET",
      headers: headers,
      body: opts.body ? JSON.stringify(opts.body) : undefined
    });
    if (res.status === 401 || res.status === 403) {
      LS.removeItem("id_token");
      startLogin();
      throw new Error("Sesion expirada");
    }
    const text = await res.text();
    const data = text ? safeJson(text) : null;
    if (!res.ok) {
      const msg = (data && (data.message || data.error)) || ("HTTP " + res.status);
      throw new Error(msg);
    }
    return data;
  }
  function safeJson(t) { try { return JSON.parse(t); } catch (_) { return null; } }

  /* ----------------------- UI: toasts --------------------------*/
  function toast(message, kind) {
    const el = document.createElement("div");
    el.className = "toast toast--" + (kind || "ok");
    el.setAttribute("role", kind === "err" ? "alert" : "status");
    el.textContent = message;
    els.toastStack.appendChild(el);
    setTimeout(() => {
      el.classList.add("is-leaving");
      setTimeout(() => el.remove(), 220);
    }, 4000);
  }

  /* ----------------------- UI: preview -------------------------*/
  let previewTimer = null;
  function updatePreview() {
    const html = els.bodyInput.value || "";
    const frame = els.previewFrame;
    const doc = frame.contentDocument || frame.contentWindow.document;
    doc.open();
    doc.write(html);
    doc.close();
  }
  function schedulePreview() {
    if (previewTimer) clearTimeout(previewTimer);
    previewTimer = setTimeout(updatePreview, 300);
  }

  /* ----------------------- UI: history -------------------------*/
  function fmtDate(iso) {
    if (!iso) return "\u2014";
    const d = new Date(iso);
    if (isNaN(d.getTime())) return String(iso);
    return d.toLocaleDateString("es-ES", { year: "numeric", month: "short", day: "2-digit" })
      + " \u00B7 " + d.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });
  }
  function statusPill(status) {
    const s = String(status || "").toLowerCase();
    const span = document.createElement("span");
    span.className = "pill pill--neutral";
    let label = status ? String(status) : "\u2014";
    if (s === "sent" || s === "enviada" || s === "success" || s === "completed") {
      span.className = "pill pill--ok"; label = "Enviada";
    } else if (s === "failed" || s === "error") {
      span.className = "pill pill--err"; label = "Error";
    } else if (s === "sending" || s === "processing" || s === "pending") {
      span.className = "pill pill--neutral"; label = "En curso";
    }
    span.textContent = label;
    return span;
  }
  function td(text, className) {
    const cell = document.createElement("td");
    if (className) cell.className = className;
    cell.textContent = text == null ? "\u2014" : String(text);
    return cell;
  }
  function renderHistory(items) {
    items = Array.isArray(items) ? items : [];
    const body = els.historyBody;
    while (body.firstChild) body.removeChild(body.firstChild);

    if (!items.length) {
      els.historyTable.hidden = true;
      els.historyEmpty.hidden = false;
      return;
    }
    els.historyEmpty.hidden = true;
    els.historyTable.hidden = false;

    const frag = document.createDocumentFragment();
    items.slice(0, 10).forEach(c => {
      const tr = document.createElement("tr");
      const date = c.sent_at || c.created_at || c.date;
      const subject = c.subject || "(sin asunto)";
      const topic = c.topic || "\u2014";
      const recipients = c.recipients != null ? c.recipients
        : (c.sent_count != null ? c.sent_count : "\u2014");

      tr.appendChild(td(fmtDate(date), "history__date"));
      tr.appendChild(td(subject, "history__subject"));
      tr.appendChild(td(topic));
      tr.appendChild(td(recipients, "num"));

      const statusCell = document.createElement("td");
      statusCell.appendChild(statusPill(c.status));
      tr.appendChild(statusCell);

      frag.appendChild(tr);
    });
    body.appendChild(frag);
  }
  async function loadHistory() {
    try {
      const data = await api("/admin/campaigns");
      const items = Array.isArray(data) ? data : (data && data.items) || [];
      renderHistory(items);
    } catch (e) {
      renderHistory([]);
      toast("No pudimos cargar el historial: " + e.message, "err");
    }
  }

  /* ----------------------- Send flows --------------------------*/
  function validateBase() {
    if (!els.subject.value.trim()) { toast("Anade un asunto.", "err"); els.subject.focus(); return false; }
    if (!els.bodyInput.value.trim()) { toast("El cuerpo HTML no puede estar vacio.", "err"); els.bodyInput.focus(); return false; }
    return true;
  }
  function payload() {
    return {
      subject: els.subject.value.trim(),
      body_html: els.bodyInput.value,
      topic: els.topic.value
    };
  }
  function parseEmails(raw) {
    return (raw || "")
      .split(/[,;\s]+/)
      .map(s => s.trim())
      .filter(Boolean);
  }
  function setBusy(btn, busy, busyLabel) {
    if (!btn) return;
    if (busy) {
      btn.dataset.prevLabel = btn.textContent;
      btn.textContent = busyLabel || "Enviando\u2026";
      btn.classList.add("is-busy");
      btn.disabled = true;
    } else {
      if (btn.dataset.prevLabel) btn.textContent = btn.dataset.prevLabel;
      btn.classList.remove("is-busy");
      btn.disabled = false;
    }
  }

  async function sendTest() {
    if (!validateBase()) return;
    const recipients = parseEmails(els.testEmails.value);
    if (!recipients.length) { toast("Anade al menos un email de prueba.", "err"); els.testEmails.focus(); return; }
    setBusy(els.sendTestBtn, true, "Enviando prueba\u2026");
    try {
      await api("/admin/campaigns/test", {
        method: "POST",
        body: Object.assign({}, payload(), { recipients: recipients })
      });
      toast("Prueba enviada a " + recipients.length + " destinatarios.", "ok");
    } catch (e) {
      toast("Error al enviar prueba: " + e.message, "err");
    } finally {
      setBusy(els.sendTestBtn, false);
    }
  }

  async function fetchAudienceCount() {
    try {
      const data = await api("/admin/audience/count?topic=" + encodeURIComponent(els.topic.value));
      if (data && typeof data.count === "number") return data.count;
      if (typeof data === "number") return data;
    } catch (_) {}
    return null;
  }

  async function sendAll() {
    if (!validateBase()) return;
    setBusy(els.sendAllBtn, true, "Preparando\u2026");
    const count = await fetchAudienceCount();
    setBusy(els.sendAllBtn, false);
    if (count == null) {
      toast("No pudimos obtener el tamano de la lista.", "err");
      return;
    }
    if (count === 0) {
      toast("No hay suscriptoras en este topic.", "err");
      return;
    }
    els.confirmCount.textContent = count.toLocaleString("es-ES");
    const result = await openDialog();
    if (result !== "confirm") return;

    setBusy(els.sendAllBtn, true, "Enviando\u2026");
    try {
      await api("/admin/campaigns", { method: "POST", body: payload() });
      toast("Campana lanzada a " + count.toLocaleString("es-ES") + " personas.", "ok");
      loadHistory();
    } catch (e) {
      toast("Error al enviar: " + e.message, "err");
    } finally {
      setBusy(els.sendAllBtn, false);
    }
  }

  function openDialog() {
    return new Promise(resolve => {
      const d = els.dialog;
      if (typeof d.showModal !== "function") {
        resolve(window.confirm("Enviar a " + els.confirmCount.textContent + " personas?") ? "confirm" : "cancel");
        return;
      }
      function onClose() {
        d.removeEventListener("close", onClose);
        resolve(d.returnValue || "cancel");
      }
      d.addEventListener("close", onClose);
      d.returnValue = "";
      d.showModal();
    });
  }

  /* ----------------------- Wire-up -----------------------------*/
  function wire() {
    els.bodyInput.addEventListener("blur", updatePreview);
    els.bodyInput.addEventListener("input", schedulePreview);
    els.sendTestBtn.addEventListener("click", sendTest);
    els.sendAllBtn.addEventListener("click", sendAll);
    els.logoutBtn.addEventListener("click", logout);
    els.form.addEventListener("submit", e => e.preventDefault());
    updatePreview();
  }

  function showUser() {
    const claims = parseJwt(LS.getItem("id_token"));
    const email = (claims && (claims.email || claims["cognito:username"])) || "";
    els.userEmail.textContent = email;
  }

  function reveal() {
    els.body.classList.remove("is-loading");
    els.layout.hidden = false;
    els.boot.classList.add("is-hidden");
    setTimeout(() => { if (els.boot) els.boot.remove(); }, 300);
  }

  function renderBootError(text) {
    const boot = document.getElementById("boot");
    if (!boot) return;
    while (boot.firstChild) boot.removeChild(boot.firstChild);
    const p = document.createElement("p");
    p.style.cssText = "font-family:var(--ff-sans);color:var(--danger);max-width:380px;text-align:center;";
    p.textContent = text;
    boot.appendChild(p);
  }

  async function init() {
    if (!cfg.cognitoDomain || !cfg.cognitoClientId || !cfg.redirectUri || !cfg.apiBase) {
      renderBootError("Falta configuracion del admin. Ejecuta deploy.sh antes de servir esta pagina.");
      return;
    }
    if (!tokenIsFresh()) {
      await startLogin();
      return;
    }
    showUser();
    wire();
    reveal();
    loadHistory();
  }

  init();
})();
