import { GetCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import { UpdateContactCommand } from "@aws-sdk/client-sesv2";
import {
  ses,
  ddb,
  isValidEmail,
  normalizeEmail,
  log,
  htmlResponse,
  brandedPage,
} from "./_shared.mjs";

export const handler = async (event) => {
  const qs = event?.queryStringParameters || {};
  const token = qs.token;
  const contactParam = qs.contact; // SES native unsubscribe link passes ?contact=<email>&list=<name>
  const listParam = qs.list;
  const listName = process.env.CONTACT_LIST_NAME;
  const topicName = process.env.TOPIC_NAME || "promociones";

  try {
    let email = null;

    if (contactParam && isValidEmail(contactParam)) {
      email = normalizeEmail(contactParam);
      // If the list param is present, sanity-check it matches our configured list.
      if (listParam && listParam !== listName) {
        log("warn", "unsubscribe_list_mismatch", { listParam });
      }
    } else if (token && typeof token === "string") {
      const res = await ddb.send(
        new GetCommand({ TableName: process.env.TOKENS_TABLE_NAME, Key: { token } })
      );
      if (res?.Item?.email) {
        email = normalizeEmail(res.Item.email);
        // Best-effort cleanup of one-shot token.
        await ddb
          .send(new DeleteCommand({ TableName: process.env.TOKENS_TABLE_NAME, Key: { token } }))
          .catch(() => {});
      }
    }

    if (!email) {
      return htmlResponse(
        400,
        brandedPage({
          title: "Enlace no válido",
          heading: "Enlace no válido",
          message:
            "No hemos podido identificar tu suscripción. Si quieres darte de baja, responde a cualquiera de nuestros emails y lo haremos manualmente.",
          ctaLabel: "Volver al inicio",
        })
      );
    }

    await ses.send(
      new UpdateContactCommand({
        ContactListName: listName,
        EmailAddress: email,
        TopicPreferences: [{ TopicName: topicName, SubscriptionStatus: "OPT_OUT" }],
        UnsubscribeAll: true,
      })
    );

    log("info", "contact_opted_out", { email });

    return htmlResponse(
      200,
      brandedPage({
        title: "Baja confirmada",
        heading: "Has cancelado tu suscripción",
        message:
          "Ya no recibirás más correos promocionales. Esperamos verte pronto por el estudio.",
        ctaLabel: "Volver al inicio",
      })
    );
  } catch (err) {
    log("error", "unsubscribe_failed", { err: String(err?.name || err), msg: err?.message });
    return htmlResponse(
      500,
      brandedPage({
        title: "Error",
        heading: "Algo ha ido mal",
        message:
          "No hemos podido procesar tu baja en este momento. Inténtalo de nuevo en unos minutos o respóndenos por email.",
        ctaLabel: "Volver al inicio",
      })
    );
  }
};
