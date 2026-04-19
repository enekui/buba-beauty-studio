import { randomBytes } from "node:crypto";
import { GetContactCommand, SendEmailCommand } from "@aws-sdk/client-sesv2";
import { PutCommand } from "@aws-sdk/lib-dynamodb";
import {
  ses,
  ddb,
  isValidEmail,
  normalizeEmail,
  nowEpoch,
  nowIso,
  log,
  jsonResponse,
  parseBody,
} from "./_shared.mjs";

const TOKEN_TTL_SECONDS = 72 * 60 * 60; // 72h

export const handler = async (event) => {
  // CORS preflight
  if (event?.requestContext?.http?.method === "OPTIONS" || event?.httpMethod === "OPTIONS") {
    return jsonResponse(event, 204, {});
  }

  try {
    const body = parseBody(event);
    if (body === null) return jsonResponse(event, 400, { error: "JSON inválido." });

    const email = normalizeEmail(body.email);
    const consent = body.consent === true;
    const source = typeof body.source === "string" ? body.source.slice(0, 120) : "landing";
    const locale = typeof body.locale === "string" ? body.locale.slice(0, 10) : "es";

    if (!consent || !isValidEmail(email)) {
      return jsonResponse(event, 400, {
        error: "Email no válido o consentimiento no otorgado.",
      });
    }

    const listName = process.env.CONTACT_LIST_NAME;
    const topicName = process.env.TOPIC_NAME || "promociones";

    // Idempotency: if the contact already exists and is OPT_IN for this topic, skip.
    try {
      const existing = await ses.send(
        new GetContactCommand({ ContactListName: listName, EmailAddress: email })
      );
      const prefs = existing?.TopicPreferences || [];
      const optedIn = prefs.some(
        (p) => p.TopicName === topicName && p.SubscriptionStatus === "OPT_IN"
      );
      if (optedIn) {
        log("info", "already_subscribed", { email });
        return jsonResponse(event, 200, {
          status: "already_subscribed",
          message: "Ya estás suscrita. ¡Gracias!",
        });
      }
    } catch (err) {
      if (err?.name !== "NotFoundException") {
        // Unknown error — log and continue with the confirmation flow.
        log("warn", "get_contact_failed", { email, err: String(err?.name || err) });
      }
    }

    const token = randomBytes(32).toString("hex");
    const createdAt = nowIso();
    const ttl = nowEpoch() + TOKEN_TTL_SECONDS;

    await ddb.send(
      new PutCommand({
        TableName: process.env.TOKENS_TABLE_NAME,
        Item: { token, email, consent, source, locale, createdAt, ttl },
      })
    );

    const confirmUrl = `${process.env.CONFIRM_BASE_URL}/confirm?token=${token}`;
    const templateName = process.env.CONFIRM_TEMPLATE_NAME || "confirm_opt_in";

    await ses.send(
      new SendEmailCommand({
        FromEmailAddress: `${process.env.SENDER_FROM_NAME} <${process.env.SENDER_FROM_EMAIL}>`,
        ReplyToAddresses: process.env.REPLY_TO_EMAIL ? [process.env.REPLY_TO_EMAIL] : undefined,
        Destination: { ToAddresses: [email] },
        ConfigurationSetName: process.env.CONFIGURATION_SET_NAME,
        Content: {
          Template: {
            TemplateName: templateName,
            TemplateData: JSON.stringify({
              confirm_url: confirmUrl,
              confirm_expires_in: "72 horas",
            }),
          },
        },
      })
    );

    log("info", "confirmation_email_sent", { email, source });
    return jsonResponse(event, 200, {
      status: "pending",
      message: "Revisa tu bandeja de entrada para confirmar tu suscripción.",
    });
  } catch (err) {
    log("error", "subscribe_failed", { err: String(err?.name || err), msg: err?.message });
    return jsonResponse(event, 500, { error: "No hemos podido procesar tu suscripción." });
  }
};
