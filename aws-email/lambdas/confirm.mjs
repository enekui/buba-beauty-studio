import {
  CreateContactCommand,
  UpdateContactCommand,
} from "@aws-sdk/client-sesv2";
import { GetCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import {
  ses,
  ddb,
  nowEpoch,
  log,
  htmlResponse,
  brandedPage,
} from "./_shared.mjs";

export const handler = async (event) => {
  const token = event?.queryStringParameters?.token;
  const listName = process.env.CONTACT_LIST_NAME;
  const topicName = process.env.TOPIC_NAME || "promociones";

  if (!token || typeof token !== "string" || token.length < 16) {
    return htmlResponse(
      410,
      brandedPage({
        title: "Enlace no válido",
        heading: "Enlace no válido",
        message: "El enlace de confirmación no es correcto. Vuelve a suscribirte desde nuestra web.",
        ctaLabel: "Volver al inicio",
      })
    );
  }

  try {
    const res = await ddb.send(
      new GetCommand({ TableName: process.env.TOKENS_TABLE_NAME, Key: { token } })
    );
    const item = res?.Item;

    if (!item || (item.ttl && item.ttl < nowEpoch())) {
      log("info", "token_expired_or_missing", { token: token.slice(0, 8) });
      return htmlResponse(
        410,
        brandedPage({
          title: "Enlace caducado",
          heading: "Este enlace ha caducado",
          message:
            "El enlace de confirmación ya no es válido. Vuelve a suscribirte desde bubabeautystudio.com para recibir nuestras promociones.",
          ctaLabel: "Volver al inicio",
        })
      );
    }

    const email = item.email;
    const topicPrefs = [{ TopicName: topicName, SubscriptionStatus: "OPT_IN" }];

    try {
      await ses.send(
        new CreateContactCommand({
          ContactListName: listName,
          EmailAddress: email,
          TopicPreferences: topicPrefs,
          UnsubscribeAll: false,
          AttributesData: JSON.stringify({ source: item.source || "landing", locale: item.locale || "es" }),
        })
      );
    } catch (err) {
      if (err?.name === "AlreadyExistsException") {
        await ses.send(
          new UpdateContactCommand({
            ContactListName: listName,
            EmailAddress: email,
            TopicPreferences: topicPrefs,
            UnsubscribeAll: false,
          })
        );
      } else {
        throw err;
      }
    }

    await ddb.send(
      new DeleteCommand({ TableName: process.env.TOKENS_TABLE_NAME, Key: { token } })
    );

    log("info", "contact_opted_in", { email });

    return htmlResponse(
      200,
      brandedPage({
        title: "Suscripción confirmada",
        heading: "¡Listo! Ya estás suscrita",
        message:
          "Gracias por confirmar. Te avisaremos de nuestras promociones y novedades con mimo, sin saturarte.",
        ctaLabel: "Volver al inicio",
      })
    );
  } catch (err) {
    log("error", "confirm_failed", { err: String(err?.name || err), msg: err?.message });
    return htmlResponse(
      500,
      brandedPage({
        title: "Error",
        heading: "Algo ha ido mal",
        message: "No hemos podido confirmar tu suscripción en este momento. Inténtalo de nuevo en unos minutos.",
        ctaLabel: "Volver al inicio",
      })
    );
  }
};
