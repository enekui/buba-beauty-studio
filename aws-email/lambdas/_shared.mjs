import { SESv2Client } from "@aws-sdk/client-sesv2";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";

// Singleton clients reused across invocations within the same execution environment.
const REGION = process.env.AWS_REGION || "eu-west-1";

export const ses = new SESv2Client({ region: REGION });

const rawDdb = new DynamoDBClient({ region: REGION });
export const ddb = DynamoDBDocumentClient.from(rawDdb, {
  marshallOptions: { removeUndefinedValues: true, convertEmptyValues: false },
});

// RFC 5322 simplified — good enough for a landing page subscription form.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export const isValidEmail = (email) => typeof email === "string" && EMAIL_RE.test(email.trim());

export const normalizeEmail = (email) => (email || "").trim().toLowerCase();

export const nowEpoch = () => Math.floor(Date.now() / 1000);

export const nowIso = () => new Date().toISOString();

export function log(level, message, extra = {}) {
  const line = { ts: nowIso(), level, message, ...extra };
  // CloudWatch picks up stdout lines. Keep them structured JSON.
  console.log(JSON.stringify(line));
}

// CORS helper — echoes the request Origin back when it matches the allowlist.
export function corsHeaders(event) {
  const raw = process.env.CORS_ALLOWED_ORIGINS || "";
  const allowed = raw.split(",").map((s) => s.trim()).filter(Boolean);
  const origin = event?.headers?.origin || event?.headers?.Origin || "";
  const allowOrigin = allowed.includes("*")
    ? "*"
    : allowed.includes(origin)
      ? origin
      : allowed[0] || "";
  const headers = {
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Max-Age": "600",
    "Content-Type": "application/json; charset=utf-8",
  };
  if (allowOrigin) headers["Access-Control-Allow-Origin"] = allowOrigin;
  return headers;
}

export function jsonResponse(event, statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders(event),
    body: JSON.stringify(body),
  };
}

export function htmlResponse(statusCode, html) {
  return {
    statusCode,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
    body: html,
  };
}

// Minimal Buba-branded HTML page. Cream #FAF7F4 background, gold #C9A87C accent,
// Cormorant Garamond (display) + DM Sans (body) from Google Fonts.
export function brandedPage({ title, heading, message, ctaLabel, ctaHref }) {
  const rootDomain = process.env.ROOT_DOMAIN || "bubabeautystudio.com";
  const homeHref = `https://${rootDomain}`;
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex" />
<title>${title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@400;500;600&family=DM+Sans:wght@300;400;500&display=swap" rel="stylesheet" />
<style>
  :root { --cream: #FAF7F4; --gold: #C9A87C; --ink: #2B2623; --muted: #7A6F66; }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: var(--cream); color: var(--ink); font-family: "DM Sans", system-ui, sans-serif; }
  body { min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 2rem; }
  .card { max-width: 520px; width: 100%; text-align: center; padding: 3rem 2.25rem; border: 1px solid rgba(201,168,124,0.25); background: #fff; border-radius: 2px; }
  .mark { font-family: "Cormorant Garamond", serif; font-size: 0.95rem; letter-spacing: 0.35em; text-transform: uppercase; color: var(--gold); margin-bottom: 2.25rem; }
  h1 { font-family: "Cormorant Garamond", serif; font-weight: 500; font-size: 2.25rem; line-height: 1.2; margin: 0 0 1rem; }
  p { font-size: 1rem; line-height: 1.6; color: var(--muted); margin: 0 0 2rem; font-weight: 300; }
  a.cta { display: inline-block; padding: 0.9rem 2.2rem; border: 1px solid var(--gold); color: var(--ink); text-decoration: none; font-size: 0.85rem; letter-spacing: 0.2em; text-transform: uppercase; transition: background 0.25s ease, color 0.25s ease; }
  a.cta:hover { background: var(--gold); color: #fff; }
  .rule { width: 40px; height: 1px; background: var(--gold); margin: 0 auto 1.5rem; }
</style>
</head>
<body>
  <main class="card">
    <div class="mark">Buba Beauty Studio</div>
    <div class="rule"></div>
    <h1>${heading}</h1>
    <p>${message}</p>
    ${ctaLabel ? `<a class="cta" href="${ctaHref || homeHref}">${ctaLabel}</a>` : ""}
  </main>
</body>
</html>`;
}

// Safe JSON.parse for event bodies (may be base64 from API Gateway).
export function parseBody(event) {
  if (!event || !event.body) return {};
  let raw = event.body;
  if (event.isBase64Encoded) raw = Buffer.from(raw, "base64").toString("utf-8");
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
